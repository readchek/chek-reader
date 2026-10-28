public import ChekReaderCore
import Foundation
public import Observation

/// Drives one reading session at a time.
///
/// Every `open` starts a new session and cancels the previous one. Work
/// that finishes after its session was replaced is dropped, so a slow open
/// can never overwrite a newer one.
@MainActor
@Observable
public final class ReaderController {
    public enum State: Equatable, Sendable {
        case idle
        case opening
        case ready
        case failed(ReaderError)
        case closing
        case closed
    }

    public private(set) var state: State = .idle
    /// The format of the current session, once it is known.
    public private(set) var format: ReaderFormat?
    /// The open publication, once the session is ready.
    public private(set) var publication: Publication?
    /// The current position. Observing it does not redraw views that only
    /// read ``state``.
    public private(set) var location: Locator?
    /// Fixed positions through the publication, worked out in the
    /// background once it opens. Until then, locations have no
    /// ``Locator/Locations/position`` or ``Locator/Locations/totalProgression``.
    public private(set) var positions: PositionList?
    /// The reading settings applied to reflowable text. Set them with
    /// ``setPreferences(_:)``.
    public private(set) var preferences: ReaderPreferences
    /// Counts taps in the middle of the page, where a tap doesn't turn it.
    /// Apps watch it to show and hide their own controls.
    public private(set) var middleTapCount = 0
    /// Counts page turns asked for past the last page, by a tap, swipe,
    /// key or pulling a scrolled comic up past its end. Apps watch it to
    /// go on to whatever comes next, such as a series' next chapter, so
    /// reading on never needs a button.
    public private(set) var turnsPastEnd = 0

    /// The limits applied to every publication this controller opens.
    public let limits: ReaderLimits
    /// Whether publications may run their own scripts. Off by default;
    /// the reader's own scripts run either way.
    public let allowsPublicationScripts: Bool

    /// Identifies the current session. Work tagged with an older value is stale.
    @ObservationIgnored private(set) var session = 0
    /// What the current session opened, to open again when a preference
    /// needs the publication parsed afresh.
    @ObservationIgnored private var source: PublicationSource?
    @ObservationIgnored private weak var navigator: (any ReaderNavigator)?

    public init(
        limits: ReaderLimits = .default,
        allowsPublicationScripts: Bool = false,
        preferences: ReaderPreferences = ReaderPreferences()
    ) {
        self.limits = limits
        self.allowsPublicationScripts = allowsPublicationScripts
        self.preferences = preferences
    }

    /// Opens a publication, replacing any open session.
    ///
    /// Returns once the publication is parsed and ready to show. If another
    /// `open` or ``close()`` starts first, this call returns without
    /// changing state.
    public func open(_ source: PublicationSource, at location: Locator? = nil) async throws(ReaderError) {
        session += 1
        let current = session
        state = .opening
        format = nil
        publication = nil
        positions = nil
        navigator = nil
        self.source = source
        self.location = location

        let detected: ReaderFormat?
        do {
            detected = try await FormatSniffer.format(of: source)
        } catch {
            guard current == session else { return }
            return try fail(error)
        }
        guard current == session else { return }

        guard let detected else {
            return try fail(.unsupportedFormat(fileName: source.fileName))
        }
        format = detected
        let module: any ReaderFormatModule.Type
        do {
            module = try ReaderFormats.module(for: detected)
        } catch {
            return try fail(error)
        }

        var opened: Publication
        do {
            opened = try await module.open(source, format: detected, limits: limits)
        } catch {
            guard current == session else { return }
            return try fail(error)
        }
        guard current == session else { return }
        if let readingProgression = preferences.readingProgression {
            opened = opened.withReadingProgression(readingProgression)
        }

        guard NavigatorKind(opened) != nil else {
            return try fail(.notYetImplemented(detected))
        }
        if let location, opened.readingOrderIndex(of: location) == nil {
            self.location = nil
        }
        self.location = self.location ?? opened.startLocator
        publication = opened
        state = .ready

        // Positions can mean reading every resource, so they don't hold up
        // opening. Locations reported before they're ready get them later.
        Task { [weak self] in
            guard let positions = try? await opened.positions() else { return }
            self?.didFindPositions(positions, session: current)
        }
    }

    private func didFindPositions(_ positions: PositionList, session: Int) {
        guard session == self.session, state == .ready else { return }
        self.positions = positions
        if let location {
            self.location = located(location)
        }
    }

    /// Ends the session.
    public func close() async {
        session += 1
        navigator = nil
        source = nil
        guard state != .idle, state != .closed else { return }
        state = .closing
        publication = nil
        positions = nil
        state = .closed
    }

    // MARK: - Navigation

    /// Moves to `locator`. Returns `false` when it isn't in the publication.
    @discardableResult
    public func go(to locator: Locator) async -> Bool {
        guard state == .ready, let publication, publication.readingOrderIndex(of: locator) != nil else {
            return false
        }
        guard let navigator else {
            // No view is showing the publication yet, so it opens here when one appears.
            location = located(locator)
            return true
        }
        return await navigator.go(to: locator)
    }

    /// Moves to a table of contents entry or other link.
    @discardableResult
    public func go(to link: Link) async -> Bool {
        guard let locator = publication?.locator(for: link) else { return false }
        return await go(to: locator)
    }

    /// Moves forward one page, or one chapter when nothing is displayed.
    /// Returns `false` at the end of the publication.
    @discardableResult
    public func goForward() async -> Bool {
        guard state == .ready else { return false }
        if let navigator {
            return await navigator.goForward()
        }
        return await goToChapter(offset: 1)
    }

    /// Moves back one page, or one chapter when nothing is displayed.
    /// Returns `false` at the start of the publication.
    @discardableResult
    public func goBackward() async -> Bool {
        guard state == .ready else { return false }
        if let navigator {
            return await navigator.goBackward()
        }
        return await goToChapter(offset: -1)
    }

    /// Moves to a 1-based position in ``positions``. Returns `false` before
    /// positions are ready or when it's out of range.
    @discardableResult
    public func go(toPosition position: Int) async -> Bool {
        guard let locator = positions?.locator(at: position) else { return false }
        return await go(to: locator)
    }

    /// Changes the reading settings. The text is laid out again with the
    /// same passage on screen.
    public func setPreferences(_ preferences: ReaderPreferences) async {
        guard preferences != self.preferences else { return }
        let reopens = preferences.readingProgression != self.preferences.readingProgression
        self.preferences = preferences
        if reopens, state == .ready, let source {
            // The direction is baked into every navigator's layout, so the
            // publication opens again, at the same place.
            try? await open(source, at: location)
        } else {
            await navigator?.apply(preferences)
        }
    }

    /// Finds `query` in the open publication.
    ///
    /// Each result is a ``Locator`` that ``go(to:)`` opens at the page
    /// holding the match, with the matched text and some text around it,
    /// and its position once ``positions`` are ready. Finds nothing when no
    /// publication is open, or when the session changes while searching.
    public func search(for query: String, options: SearchOptions = SearchOptions()) async throws(ReaderError) -> [Locator] {
        guard state == .ready, let publication else { return [] }
        let current = session
        let found = try await publication.search(for: query, options: options)
        guard current == session else { return [] }
        return found.map(located)
    }

    private func goToChapter(offset: Int) async -> Bool {
        guard let publication, let location, let index = publication.readingOrderIndex(of: location) else {
            return false
        }
        let target = index + offset
        guard publication.readingOrder.indices.contains(target),
              let locator = publication.locator(for: publication.readingOrder[target])
        else { return false }
        self.location = located(locator)
        return true
    }

    /// `locator` with its position filled in, once positions are ready.
    private func located(_ locator: Locator) -> Locator {
        guard let positions, let index = publication?.readingOrderIndex(of: locator) else { return locator }
        return positions.locate(locator, inResource: index)
    }

    // MARK: - Navigators

    /// Connects the view showing `session`. Returns `false` when the session
    /// has already been replaced.
    func attach(_ navigator: any ReaderNavigator, session: Int) -> Bool {
        guard session == self.session, state == .ready else { return false }
        self.navigator = navigator
        return true
    }

    /// Records where a navigator moved to, unless its session is stale.
    func navigator(session: Int, didMoveTo locator: Locator) {
        guard session == self.session, state == .ready else { return }
        let moved = located(locator)
        guard moved != location else { return }
        location = moved
    }

    /// Records a tap in the middle of the page, unless its session is stale.
    func navigatorDidTapMiddle(session: Int) {
        guard session == self.session, state == .ready else { return }
        middleTapCount += 1
    }

    /// Records a turn asked for past the last page, unless its session is stale.
    func navigatorDidTurnPastEnd(session: Int) {
        guard session == self.session, state == .ready else { return }
        turnsPastEnd += 1
    }

    private func fail(_ error: ReaderError) throws(ReaderError) {
        state = .failed(error)
        throw error
    }
}

/// The kind of view that shows a publication.
enum NavigatorKind: Equatable, Sendable {
    /// Web pages laid out by the reader script, for HTML and SVG.
    case web
    /// PDFKit.
    case pdf
    /// Page images decoded with ImageIO, for comics.
    case images

    /// The kind that can show every resource in `publication`'s reading
    /// order, or `nil` when none can.
    init?(_ publication: Publication) {
        let types = publication.readingOrder.map { $0.mediaType ?? MediaType.forPath($0.path) }
        guard !types.isEmpty else { return nil }
        if types == ["application/pdf"] {
            self = .pdf
        } else if [.cbz, .cbt, .cbr, .cb7].contains(publication.format) {
            // Streamed pages have no media type until they're read.
            self = .images
        } else if types.allSatisfy({ MediaType.isHTML($0) || $0.hasPrefix("image/") }) {
            self = .web
        } else {
            return nil
        }
    }
}

/// A view that shows a publication and moves through it, such as the web
/// navigator for reflowable text.
@MainActor
protocol ReaderNavigator: AnyObject {
    func go(to locator: Locator) async -> Bool
    func goForward() async -> Bool
    func goBackward() async -> Bool
    /// Applies new reading settings, keeping the same passage on screen.
    func apply(_ preferences: ReaderPreferences) async
}
