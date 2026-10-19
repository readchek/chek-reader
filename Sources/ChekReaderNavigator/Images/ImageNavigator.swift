#if canImport(ImageIO) && canImport(SwiftUI)
import ChekReaderCore
import CoreGraphics
import Foundation
import Observation

/// Shows a comic a page at a time.
///
/// Pages decode with ImageIO off the main thread, straight to the size
/// they're shown at. The pages either side of the one on screen are decoded
/// ahead, so a turn shows a page that's already in memory, and pages
/// further away are dropped.
@MainActor
@Observable
final class ImageNavigator: ReaderNavigator {
    /// The reading order index of the page on screen.
    private(set) var index: Int?
    /// The page on screen, decoded, for platforms without the pager.
    private(set) var image: CGImage?
    /// How pages turn. The pager is rebuilt when it changes.
    private(set) var pageTransition: ReaderPreferences.PageTransition
    /// The flow asked for; ``isScrolled`` is what it resolved to.
    @ObservationIgnored private var comicFlow: ReaderPreferences.ComicFlow
    /// Whether pages show in one vertical column rather than one at a
    /// time. `nil` until ``start()`` has looked at the pages.
    private(set) var isScrolled: Bool?
    /// Whether pages run right to left, as in manga.
    let isRightToLeft: Bool
    /// The page-turning view showing the pages, when there is one. It
    /// animates every turn, including ones asked for by keys or the scrubber.
    @ObservationIgnored weak var pager: (any ImagePaging)?

    @ObservationIgnored let publication: Publication
    @ObservationIgnored private weak var controller: ReaderController?
    @ObservationIgnored private let session: Int
    @ObservationIgnored private var decoded: [Int: CGImage] = [:]
    @ObservationIgnored private var loading: [Int: Task<CGImage?, Never>] = [:]
    /// Increases with every navigation, so a superseded one is dropped.
    @ObservationIgnored private var generation = 0
    /// The longest side, in pixels, pages decode to.
    @ObservationIgnored private var maxPixelSize = 2048
    /// The screen's width in pixels, which tall pages decode wide enough to fill.
    @ObservationIgnored private var widthPixels = 0
    /// The first page of each table of contents entry, for locator titles.
    @ObservationIgnored private let chapters: [(page: Int, title: String)]

    /// How many pages either side of the current one stay decoded.
    private static let window = 2

    init(controller: ReaderController, publication: Publication) {
        self.controller = controller
        self.publication = publication
        session = controller.session
        pageTransition = controller.preferences.pageTransition
        comicFlow = controller.preferences.comicFlow
        isRightToLeft = publication.metadata.readingProgression == .rightToLeft
        var chapters: [(page: Int, title: String)] = []
        for link in publication.tableOfContents {
            if let title = link.title, let page = publication.readingOrder.firstIndex(where: { $0.path == link.path }) {
                chapters.append((page, title))
            }
        }
        self.chapters = chapters.sorted { $0.page < $1.page }
    }

    /// Connects to the controller and shows its current location.
    func start() async {
        isScrolled = await resolveScrolled()
        guard let controller, controller.attach(self, session: session),
              let location = controller.location ?? publication.startLocator
        else { return }
        _ = await go(to: location)
    }

    /// Sets the size pages are shown at, decoding them again when it
    /// changes enough to matter.
    func setViewport(width: Double, height: Double, scale: Double) {
        widthPixels = Int((width * scale).rounded(.up))
        let pixels = Int((max(width, height) * scale).rounded(.up))
        guard pixels > 0, abs(pixels - maxPixelSize) * 4 > maxPixelSize else { return }
        maxPixelSize = pixels
        decoded.removeAll()
        for task in loading.values {
            task.cancel()
        }
        loading.removeAll()
        if let index {
            Task { _ = await show(index) }
        }
    }

    // MARK: - Navigation

    func go(to locator: Locator) async -> Bool {
        guard let index = publication.readingOrderIndex(of: locator) else { return false }
        return await show(index)
    }

    func goForward() async -> Bool {
        await turn(by: 1)
    }

    func goBackward() async -> Bool {
        await turn(by: -1)
    }

    /// Pages keep their publisher's look, so only the page transition applies.
    func apply(_ preferences: ReaderPreferences) async {
        pageTransition = preferences.pageTransition
        if preferences.comicFlow != comicFlow {
            comicFlow = preferences.comicFlow
            isScrolled = await resolveScrolled()
        }
    }

    var pageCount: Int {
        publication.readingOrder.count
    }

    /// Turns the page for a tap, swipe or key.
    func handle(_ input: PageCommand.Input) {
        guard let command = PageCommand(input, readingProgression: publication.metadata.readingProgression) else {
            if input == .tap(.center) {
                controller?.navigatorDidTapMiddle(session: session)
            }
            return
        }
        Task {
            switch command {
            case .forward: _ = await goForward()
            case .backward: _ = await goBackward()
            case .firstPage: _ = await show(0)
            case .lastPage: _ = await show(publication.readingOrder.count - 1)
            }
        }
    }

    private func turn(by offset: Int) async -> Bool {
        guard let index else { return false }
        let target = index + offset
        guard publication.readingOrder.indices.contains(target) else { return false }
        return await show(target)
    }

    private func show(_ target: Int) async -> Bool {
        guard publication.readingOrder.indices.contains(target) else { return false }
        if let pager {
            pager.display(page: target, animated: index != nil && index != target)
            didShow(target)
            return true
        }
        generation += 1
        let current = generation
        let page = await image(at: target)
        guard current == generation else { return false }
        index = target
        image = page
        report()
        keep(around: target)
        return page != nil
    }

    /// Webtoons are long strips meant to be scrolled, so the automatic flow
    /// scrolls when the first pages are much taller than they are wide.
    private func resolveScrolled() async -> Bool {
        switch comicFlow {
        case .paged: return false
        case .scrolled: return true
        case .automatic:
            let sample = Array(publication.readingOrder.indices.prefix(4).dropFirst(publication.readingOrder.count > 2 ? 1 : 0))
            var tall = 0
            for index in sample {
                if let image = await image(at: index), Double(image.height) > Double(image.width) * 2 {
                    tall += 1
                }
            }
            return !sample.isEmpty && tall * 2 > sample.count
        }
    }

    /// Records the page the pager settled on after a turn.
    func didShow(_ target: Int) {
        guard target != index else { return }
        index = target
        report()
        keep(around: target)
    }

    private func report() {
        guard let index, var locator = publication.locator(for: publication.readingOrder[index]) else { return }
        locator.locations.progression = 0
        if let chapter = chapters.last(where: { $0.page <= index }) {
            locator.title = chapter.title
        }
        controller?.navigator(session: session, didMoveTo: locator)
    }

    // MARK: - Decoding

    /// The page at `index`, decoded to the screen's size.
    func image(at index: Int) async -> CGImage? {
        if let image = decoded[index] {
            return image
        }
        return await (loading[index] ?? load(index)).value
    }

    /// The page at `index` decoded to `maxPixelSize`, for zooming in past
    /// the screen's size. It isn't kept, since it can be large.
    func image(at index: Int, maxPixelSize: Int) async -> CGImage? {
        guard publication.readingOrder.indices.contains(index),
              let data = try? await publication.data(at: publication.readingOrder[index].path)
        else { return nil }
        return await PageDecoder.decode(data, maxPixelSize: maxPixelSize)
    }

    private func load(_ index: Int) -> Task<CGImage?, Never> {
        let path = publication.readingOrder[index].path
        let publication = publication
        let size = maxPixelSize
        let width = widthPixels
        let task = Task { [weak self] () -> CGImage? in
            guard let data = try? await publication.data(at: path) else { return nil }
            let image = await PageDecoder.decode(data, maxPixelSize: size, minimumWidth: width)
            if let image {
                self?.didDecode(image, at: index, size: size)
            }
            return image
        }
        loading[index] = task
        return task
    }

    private func didDecode(_ image: CGImage, at index: Int, size: Int) {
        guard size == maxPixelSize else { return }
        decoded[index] = image
        loading[index] = nil
    }

    /// Decodes the pages next to `index` ahead of time and drops the rest,
    /// the next page first since reading usually goes forward.
    private func keep(around index: Int) {
        let range = (index - Self.window)...(index + Self.window)
        decoded = decoded.filter { range.contains($0.key) }
        for (page, task) in loading where !range.contains(page) {
            task.cancel()
            loading[page] = nil
        }
        for neighbor in [index + 1, index - 1, index + 2] where publication.readingOrder.indices.contains(neighbor) {
            if decoded[neighbor] == nil, loading[neighbor] == nil {
                _ = load(neighbor)
            }
        }
    }
}
/// A view that turns a comic's pages and can be told which to show.
@MainActor
protocol ImagePaging: AnyObject {
    /// Shows `page`, turning to it when `animated`.
    func display(page: Int, animated: Bool)
}
#endif
