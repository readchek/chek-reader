#if canImport(PDFKit) && canImport(SwiftUI)
import ChekReaderCore
import Foundation
import PDFKit
#if os(iOS)
import UIKit
#endif

/// Shows a PDF a page at a time with PDFKit's own view, so pages render
/// as vectors at any zoom and turn without rasterizing.
///
/// Locators point at a page with a `page=N` fragment, 1-based, and carry
/// the page's progression through the document, so positions and saved
/// locations from other Readium-compatible apps both work.
@MainActor
final class PDFNavigator: NSObject, ReaderNavigator {
    let view = PDFView()

    private let publication: Publication
    private weak var controller: ReaderController?
    private let session: Int
    /// Table of contents entries by 0-based page, for locator titles.
    private let titles: [(page: Int, title: String)]

    init(controller: ReaderController, publication: Publication) {
        self.controller = controller
        self.publication = publication
        session = controller.session
        titles = PDFPageLocation.titles(in: publication.tableOfContents)
        super.init()

        view.autoScales = true
        // PDFKit paints a gray backdrop around pages; the app draws its own
        // page color behind, so the surroundings run edge to edge in it.
        view.backgroundColor = .clear
        #if os(iOS)
        view.pageShadowsEnabled = false
        #endif
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.displaysPageBreaks = false
        view.displaysAsBook = false
        view.displaysRTL = publication.metadata.readingProgression == .rightToLeft
        #if os(iOS)
        // Swiping turns pages, as in Books.
        view.usePageViewController(true, withViewOptions: nil)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        // A double tap zooms, so a single tap waits until it can't be one.
        for recognizer in view.gestureRecognizers ?? [] {
            if let other = recognizer as? UITapGestureRecognizer, other.numberOfTapsRequired == 2 {
                tap.require(toFail: other)
            }
        }
        view.addGestureRecognizer(tap)
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)
    }

    /// Loads the document, connects to the controller and shows its
    /// current location.
    func start() async {
        guard let link = publication.readingOrder.first,
              let data = try? await publication.data(at: link.path),
              let document = PDFDocument(data: data),
              let controller, controller.attach(self, session: session)
        else { return }
        view.document = document
        #if os(iOS)
        // PDFKit's own scroll views blur and tint the page under the
        // reader's floating controls otherwise.
        func hideEdgeEffects(in view: UIView) {
            if let scrollView = view as? UIScrollView {
                scrollView.topEdgeEffect.isHidden = true
                scrollView.bottomEdgeEffect.isHidden = true
            }
            view.subviews.forEach(hideEdgeEffects)
        }
        hideEdgeEffects(in: self.view)
        #endif
        if let location = controller.location {
            _ = await go(to: location)
        }
        report()
    }

    // MARK: - Navigation

    func go(to locator: Locator) async -> Bool {
        guard let document = view.document, publication.readingOrderIndex(of: locator) != nil,
              let index = PDFPageLocation.pageIndex(of: locator, pageCount: document.pageCount),
              let page = document.page(at: index)
        else { return false }
        view.go(to: page)
        report()
        return true
    }

    func goForward() async -> Bool {
        guard view.canGoToNextPage else { return false }
        view.goToNextPage(nil)
        return true
    }

    func goBackward() async -> Bool {
        guard view.canGoToPreviousPage else { return false }
        view.goToPreviousPage(nil)
        return true
    }

    /// A PDF keeps its publisher's layout, so text size and themes don't apply.
    func apply(_ preferences: ReaderPreferences) async {}

    #if os(iOS)
    /// Turns the page for a tap at either side, as the other navigators do,
    /// and reports taps in the middle.
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let width = view.bounds.width
        guard width > 0 else { return }
        let x = recognizer.location(in: view).x / width
        let zone: PageCommand.Input.Zone = x < 0.3 ? .left : x > 0.7 ? .right : .center
        guard let command = PageCommand(.tap(zone), readingProgression: publication.metadata.readingProgression) else {
            controller?.navigatorDidTapMiddle(session: session)
            return
        }
        Task {
            switch command {
            case .forward: _ = await goForward()
            case .backward: _ = await goBackward()
            case .firstPage:
                if let page = view.document?.page(at: 0) { view.go(to: page) }
            case .lastPage:
                if let document = view.document, let page = document.page(at: document.pageCount - 1) { view.go(to: page) }
            }
        }
    }
    #endif

    @objc private func pageChanged(_ notification: Notification) {
        report()
    }

    private func report() {
        guard let document = view.document, let page = view.currentPage, let link = publication.readingOrder.first else {
            return
        }
        let index = document.index(for: page)
        guard index != NSNotFound, document.pageCount > 0 else { return }
        let locator = Locator(
            href: link.path,
            mediaType: "application/pdf",
            title: titles.last { $0.page <= index }?.title,
            locations: Locator.Locations(
                fragments: ["page=\(index + 1)"],
                progression: Double(index) / Double(document.pageCount)
            )
        )
        controller?.navigator(session: session, didMoveTo: locator)
    }
}
#endif
