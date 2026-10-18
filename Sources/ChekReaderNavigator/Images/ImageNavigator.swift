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
    /// The page on screen, decoded.
    private(set) var image: CGImage?

    @ObservationIgnored let publication: Publication
    @ObservationIgnored private weak var controller: ReaderController?
    @ObservationIgnored private let session: Int
    @ObservationIgnored private var decoded: [Int: CGImage] = [:]
    @ObservationIgnored private var loading: [Int: Task<CGImage?, Never>] = [:]
    /// Increases with every navigation, so a superseded one is dropped.
    @ObservationIgnored private var generation = 0
    /// The longest side, in pixels, pages decode to.
    @ObservationIgnored private var maxPixelSize = 2048
    /// The first page of each table of contents entry, for locator titles.
    @ObservationIgnored private let chapters: [(page: Int, title: String)]

    /// How many pages either side of the current one stay decoded.
    private static let window = 2

    init(controller: ReaderController, publication: Publication) {
        self.controller = controller
        self.publication = publication
        session = controller.session
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
        guard let controller, controller.attach(self, session: session),
              let location = controller.location ?? publication.startLocator
        else { return }
        _ = await go(to: location)
    }

    /// Sets the size pages are shown at, decoding them again when it
    /// changes enough to matter.
    func setViewport(width: Double, height: Double, scale: Double) {
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

    /// Pages keep their publisher's look, so text size and themes don't apply.
    func apply(_ preferences: ReaderPreferences) async {}

    /// Turns the page for a tap, swipe or key.
    func handle(_ input: PageCommand.Input) {
        guard let command = PageCommand(input, readingProgression: publication.metadata.readingProgression) else { return }
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

    private func report() {
        guard let index, var locator = publication.locator(for: publication.readingOrder[index]) else { return }
        locator.locations.progression = 0
        if let chapter = chapters.last(where: { $0.page <= index }) {
            locator.title = chapter.title
        }
        controller?.navigator(session: session, didMoveTo: locator)
    }

    // MARK: - Decoding

    private func image(at index: Int) async -> CGImage? {
        if let image = decoded[index] {
            return image
        }
        return await (loading[index] ?? load(index)).value
    }

    private func load(_ index: Int) -> Task<CGImage?, Never> {
        let path = publication.readingOrder[index].path
        let publication = publication
        let size = maxPixelSize
        let task = Task { [weak self] () -> CGImage? in
            guard let data = try? await publication.data(at: path) else { return nil }
            let image = await PageDecoder.decode(data, maxPixelSize: size)
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
#endif
