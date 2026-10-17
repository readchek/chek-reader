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

    /// The limits applied to every publication this controller opens.
    public let limits: ReaderLimits
    /// Whether publications may run their own scripts. Off by default;
    /// the reader's own scripts run either way.
    public let allowsPublicationScripts: Bool

    /// Identifies the current session. Work tagged with an older value is stale.
    @ObservationIgnored private(set) var session = 0
    @ObservationIgnored private weak var navigator: (any ReaderNavigator)?

    public init(limits: ReaderLimits = .default, allowsPublicationScripts: Bool = false) {
        self.limits = limits
        self.allowsPublicationScripts = allowsPublicationScripts
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
        navigator = nil
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

        let opened: Publication
        do {
            opened = try await module.open(source, format: detected, limits: limits)
        } catch {
            guard current == session else { return }
            return try fail(error)
        }
        guard current == session else { return }

        guard Self.canRender(opened) else {
            return try fail(.notYetImplemented(detected))
        }
        if let location, opened.readingOrderIndex(of: location) == nil {
            self.location = nil
        }
        self.location = self.location ?? opened.startLocator
        publication = opened
        state = .ready
    }

    /// Ends the session.
    public func close() async {
        session += 1
        navigator = nil
        guard state != .idle, state != .closed else { return }
        state = .closing
        publication = nil
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
            location = locator
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

    private func goToChapter(offset: Int) async -> Bool {
        guard let publication, let location, let index = publication.readingOrderIndex(of: location) else {
            return false
        }
        let target = index + offset
        guard publication.readingOrder.indices.contains(target),
              let locator = publication.locator(for: publication.readingOrder[target])
        else { return false }
        self.location = locator
        return true
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
        guard session == self.session, state == .ready, locator != location else { return }
        location = locator
    }

    /// Whether the navigator can show every resource in the reading order.
    static func canRender(_ publication: Publication) -> Bool {
        !publication.readingOrder.isEmpty && publication.readingOrder.allSatisfy { link in
            let type = link.mediaType ?? MediaType.forPath(link.path)
            return MediaType.isHTML(type) || type == "image/svg+xml" || type.hasPrefix("image/")
        }
    }

    private func fail(_ error: ReaderError) throws(ReaderError) {
        state = .failed(error)
        throw error
    }
}

/// A view that shows a publication and moves through it, such as the web
/// navigator for reflowable text.
@MainActor
protocol ReaderNavigator: AnyObject {
    func go(to locator: Locator) async -> Bool
    func goForward() async -> Bool
    func goBackward() async -> Bool
}
