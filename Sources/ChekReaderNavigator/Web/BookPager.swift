#if canImport(WebKit) && canImport(SwiftUI)
import CoreGraphics
import Foundation
import ImageIO

/// A page of a reflowable publication: a resource, and a page within it.
struct BookPosition: Hashable, Comparable, Sendable {
    /// Stands for a resource's last page before its page count is known.
    static let lastPage = Int.max

    var resource: Int
    var page: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.resource, lhs.page) < (rhs.resource, rhs.page)
    }
}

/// A view that turns a book's pages and can be told to turn to one.
@MainActor
protocol BookPaging: AnyObject {
    /// Turns to `position` with the page-turn animation.
    func turn(to position: BookPosition, forward: Bool) async
    /// Shows `image` over the page while the content moves underneath to
    /// picture another page.
    func cover(with image: CGImage)
    func uncover()
    /// Stops the web views panning on their own, for ones just created.
    func stopContentScrolling()
    /// Turns onto, through or back from the pages outside the book's, such
    /// as the end's own page. Returns `false` when the turn isn't one of
    /// those, so it's an ordinary page turn or none.
    func turnOutside(forward: Bool) async -> Bool
}

enum BookSnapshot {
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
#endif

#if os(iOS) && canImport(WebKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

/// Turns a book's pages with `UIPageViewController`, so a turn follows your
/// finger with a page curl or a slide.
///
/// The page on screen is the live web content, so links and text selection
/// work. The pages either side are pictures of the content, taken ahead of
/// time, which is what the turn animates. When a turn finishes on a
/// picture, the web content moves to that page underneath and takes over
/// again, looking the same.
struct BookPagerView<Content: View>: UIViewControllerRepresentable {
    let navigator: WebNavigator
    @ViewBuilder let content: () -> Content
    @Environment(\.readerEdgePages) private var edgePages

    func makeUIViewController(context: Context) -> BookPagerController<Content> {
        let hosting = UIHostingController(rootView: content())
        // The page is laid out once for the screen. Bars and the status bar
        // coming and going must not change its safe area and move the text.
        hosting.safeAreaRegions = []
        return BookPagerController(navigator: navigator, live: hosting, edgePages: edgePages)
    }

    func updateUIViewController(_ controller: BookPagerController<Content>, context: Context) {
        controller.live.rootView = content()
        controller.setEdgePages(edgePages)
    }
}

final class BookPagerController<Content: View>: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, BookPaging {
    private let navigator: WebNavigator
    let live: UIHostingController<Content>
    private lazy var liveController = LivePageController(hosting: live)
    private let isCurl: Bool
    /// The pages the app gave the book's ends, if any.
    private var edgePages: ReaderEdgePages?
    /// Kept, since a gesture recognizer doesn't keep its target.
    private var pastEndSwipe: PastEndSwipe?
    private var pastStartSwipe: PastEndSwipe?
    /// The turn waiting for the web content to catch up, so a new one
    /// doesn't start from a stale page.
    private var settling: Task<Void, Never>?

    init(navigator: WebNavigator, live: UIHostingController<Content>, edgePages: ReaderEdgePages?) {
        self.navigator = navigator
        self.live = live
        self.edgePages = edgePages
        let curl = navigator.pageTransition == .curl
        isCurl = curl
        super.init(
            transitionStyle: curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: curl ? [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)] : [.interPageSpacing: NSNumber(value: 0)]
        )
        // Set before the view loads, which is when UIKit reads it to decide
        // how many pages each turn needs.
        isDoubleSided = curl
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dataSource = self
        delegate = self
        view.semanticContentAttribute = navigator.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
        // Taps go to the content, which turns for taps at the sides and
        // shows the reader's controls for one in the middle.
        for recognizer in gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        setViewControllers(pages(for: liveController), direction: .forward, animated: false)
        navigator.pager = self
        // With pages for the ends, the turn past one is a turn onto the
        // page past it. Without, a swipe the pager has no page for is
        // still a turn past the end.
        pastEndSwipe = PastEndSwipe(in: view, isRightToLeft: navigator.isRightToLeft) { [weak self] in
            self?.isAtBoundary(.end) ?? false
        } didSwipe: { [weak self] in
            self?.navigator.didTurnPastEnd()
        }
        // The swipe back is the swipe on, mirrored.
        pastStartSwipe = PastEndSwipe(in: view, isRightToLeft: !navigator.isRightToLeft) { [weak self] in
            self?.isAtBoundary(.start) ?? false
        } didSwipe: { [weak self] in
            self?.navigator.didTurnPastStart()
        }
    }

    /// Whether a swipe toward `edge` has no page to turn to.
    private func isAtBoundary(_ edge: ReaderEdge) -> Bool {
        if let place = viewControllers?.first.flatMap(outsidePlace(of:)) {
            return place == .past(edge)
        }
        guard edgePages?.has(edge) != true else { return false }
        return edge == .end ? navigator.isAtEnd : navigator.isAtStart
    }

    /// Takes new pages for the ends, as the app learns what's either side.
    func setEdgePages(_ pages: ReaderEdgePages?) {
        let changed = pages?.start != edgePages?.start || pages?.end != edgePages?.end
        edgePages = pages
        guard isViewLoaded, let first = viewControllers?.first else { return }
        if let pages, let edgePage = first as? EdgePageController {
            edgePage.update(pages.content(edgePage.edge))
        }
        // The page view controller keeps the pages either side once it has
        // asked for them; setting the page again asks afresh.
        if changed, !(first is PastEdgePageController) {
            setViewControllers([first], direction: .forward, animated: false)
        }
    }

    private func outsidePlace(of viewController: UIViewController) -> OutsidePlace? {
        switch viewController {
        case let edge as EdgePageController: .edge(edge.edge)
        case let past as PastEdgePageController: .past(past.edge)
        default: nil
        }
    }

    private func outsidePage(_ place: OutsidePlace) -> UIViewController {
        switch place {
        case .edge(let edge):
            EdgePageController(edge: edge, content: edgePages?.content(edge) ?? AnyView(EmptyView()), pageColor: pageColor)
        case .past(let edge):
            PastEdgePageController(edge: edge, pageColor: pageColor)
        }
    }

    /// The place a turn goes to from outside place `place`, if it stays
    /// outside: past an end's page only when reading goes through it.
    private func outsidePlace(from place: OutsidePlace, forward: Bool) -> OutsidePlace? {
        guard let next = place.turned(forward: forward) else { return nil }
        if case .past(let edge) = next, place == .edge(edge), edgePages?.goesThrough(edge) != true { return nil }
        return next
    }

    /// The back of an outside page as it curls: plain, in the page's color.
    private func outsideBack(_ place: OutsidePlace) -> PageBackController {
        PageBackController(front: place, image: nil, pageColor: pageColor)
    }

    /// The outside place a turn goes to from the book's page at `position`.
    private func outsidePlace(from position: BookPosition, forward: Bool) -> OutsidePlace? {
        let edge: ReaderEdge = forward ? .end : .start
        guard edgePages?.has(edge) == true, forward ? navigator.isLast(position) : navigator.isFirst(position) else { return nil }
        return .edge(edge)
    }

    /// Tells the navigator where a turn left the pager.
    private func didSettle(on viewController: UIViewController) {
        guard let place = outsidePlace(of: viewController) else {
            navigator.didShowEdge(nil)
            return
        }
        navigator.didShowEdge(place.edge)
        if case .past(let edge) = place {
            if edge == .end {
                navigator.didTurnPastEnd()
            } else {
                navigator.didTurnPastStart()
            }
        }
    }

    func turnOutside(forward: Bool) async -> Bool {
        guard let first = viewControllers?.first else { return false }
        let target: OutsidePlace
        if let place = outsidePlace(of: first) {
            if place.isInside(afterTurning: forward) {
                // Back to the page you left, where the content still is.
                guard let position = navigator.position else { return false }
                await turn(to: position, forward: forward)
                return true
            }
            guard let next = outsidePlace(from: place, forward: forward) else { return false }
            target = next
        } else {
            guard let position = navigator.position, let next = outsidePlace(from: position, forward: forward) else { return false }
            target = next
        }
        await settling?.value
        let page = outsidePage(target)
        let animate = !UIAccessibility.isReduceMotionEnabled
        let pages = isCurl && animate ? [page, outsideBack(target)] : [page]
        await withCheckedContinuation { continuation in
            setViewControllers(pages, direction: forward ? .forward : .reverse, animated: animate) { _ in
                continuation.resume()
            }
        }
        didSettle(on: page)
        return true
    }

    /// The pages to set for `front`. A double-sided curl takes the front
    /// alone when set without animation, and the front and its back for an
    /// animated turn; anything else makes UIKit throw.
    private func pages(for front: UIViewController, animated: Bool = false) -> [UIViewController] {
        guard isCurl, animated else { return [front] }
        let position = position(of: front)
        return [front, position.map { back(of: $0, front: front) } ?? PageBackController(front: AnyHashable(0), image: nil, pageColor: pageColor)]
    }

    private func back(of position: BookPosition, front: UIViewController) -> PageBackController {
        let snapshot = (front as? SnapshotPageController)?.image
        let back = PageBackController(front: position, image: snapshot.map { UIImage(cgImage: $0) }, pageColor: pageColor)
        if snapshot == nil {
            Task { [weak back, navigator] in
                let image = await navigator.snapshot(of: position)
                back?.setImage(image.map { UIImage(cgImage: $0) })
            }
        }
        return back
    }

    /// The color of the page, from the theme the content is drawn in.
    private var pageColor: UIColor {
        navigator.pageColor ?? .systemBackground
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        navigator.viewportSize = view.bounds.size
    }

    // MARK: - BookPaging

    func turn(to position: BookPosition, forward: Bool) async {
        await settling?.value
        let image = await navigator.snapshot(of: position)
        let page = SnapshotPageController(position: position, image: image, navigator: navigator)
        let animate = !UIAccessibility.isReduceMotionEnabled
        await withCheckedContinuation { continuation in
            setViewControllers(pages(for: page, animated: animate), direction: forward ? .forward : .reverse, animated: animate) { _ in
                continuation.resume()
            }
        }
        navigator.didShowEdge(nil)
        settle(on: position)
    }

    /// Moves the web content to `position` under the picture, then shows it.
    private func settle(on position: BookPosition) {
        settling = Task { [weak self] in
            guard let self else { return }
            await navigator.move(to: position)
            // Only swap if no other turn moved on in the meantime.
            guard (viewControllers?.first as? SnapshotPageController)?.position == position else { return }
            setViewControllers(pages(for: liveController), direction: .forward, animated: false)
        }
    }

    func cover(with image: CGImage) {
        liveController.cover(with: image)
    }

    func uncover() {
        liveController.uncover()
    }

    func stopContentScrolling() {
        liveController.stopContentScrolling()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        stopContentScrolling()
    }

    // MARK: - Data source

    // With a curl, every front is followed by its back, so the page has
    // something to show as it lifts.

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if let back = viewController as? PageBackController {
            if let position = back.front.base as? BookPosition {
                return snapshotPage(at: position)
            }
            return (back.front.base as? OutsidePlace).map(outsidePage)
        }
        if let place = outsidePlace(of: viewController) {
            if place.isInside(afterTurning: false) {
                // The last page, where the content was left.
                guard let position = navigator.position else { return nil }
                let front = snapshotPage(at: position)
                return isCurl ? back(of: position, front: front) : front
            }
            return outsidePlace(from: place, forward: false).map { isCurl ? outsideBack($0) : outsidePage($0) }
        }
        guard let here = position(of: viewController) else { return nil }
        guard let target = navigator.position(before: here) else {
            return outsidePlace(from: here, forward: false).map { isCurl ? outsideBack($0) : outsidePage($0) }
        }
        let front = snapshotPage(at: target)
        return isCurl ? back(of: target, front: front) : front
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if isCurl, !(viewController is PageBackController) {
            if let place = outsidePlace(of: viewController) {
                return outsideBack(place)
            }
            if let here = position(of: viewController) {
                return back(of: here, front: viewController)
            }
        }
        let back = viewController as? PageBackController
        if let place = back?.front.base as? OutsidePlace ?? outsidePlace(of: viewController) {
            if place.isInside(afterTurning: true) {
                // The first page, where the content was left.
                return navigator.position.map(snapshotPage(at:))
            }
            return outsidePlace(from: place, forward: true).map(outsidePage)
        }
        let here = back?.front.base as? BookPosition ?? position(of: viewController)
        guard let here else { return nil }
        guard let target = navigator.position(after: here) else {
            return outsidePlace(from: here, forward: true).map(outsidePage)
        }
        return snapshotPage(at: target)
    }

    private func position(of viewController: UIViewController) -> BookPosition? {
        if let page = viewController as? SnapshotPageController {
            return page.position
        }
        if viewController is PageBackController || outsidePlace(of: viewController) != nil {
            return nil
        }
        return navigator.position
    }

    private func snapshotPage(at position: BookPosition) -> SnapshotPageController {
        SnapshotPageController(position: position, image: nil, navigator: navigator)
    }

    // MARK: - Delegate

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let first = viewControllers?.first else { return }
        didSettle(on: first)
        if let page = first as? SnapshotPageController {
            settle(on: page.position)
        }
    }
}

/// Holds the live web content as the page on screen.
private final class LivePageController: UIViewController {
    private let hosting: UIViewController
    private let coverView = UIImageView()
    /// Covers can nest when several pages are pictured at once.
    private var covers = 0

    init(hosting: UIViewController) {
        self.hosting = hosting
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        coverView.frame = view.bounds
        coverView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coverView.isHidden = true
        view.addSubview(coverView)
    }

    func cover(with image: CGImage) {
        covers += 1
        let scale = view.window?.windowScene?.screen.scale ?? traitCollection.displayScale
        coverView.image = UIImage(cgImage: image, scale: scale, orientation: .up)
        coverView.isHidden = false
    }

    func uncover() {
        covers = max(covers - 1, 0)
        if covers == 0 {
            coverView.isHidden = true
            coverView.image = nil
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        stopContentScrolling()
    }

    /// The web views must not pan between columns themselves, or their
    /// scrolling takes the drag from the page turn.
    func stopContentScrolling() {
        for scrollView in view.descendants(of: UIScrollView.self) {
            if scrollView.isScrollEnabled {
                scrollView.isScrollEnabled = false
                scrollView.panGestureRecognizer.isEnabled = false
            }
            // Web views inset their content for bars over them; the reader
            // already keeps text clear of the screen's edges, and bars that
            // come and go would move it.
            if scrollView.contentInsetAdjustmentBehavior != .never {
                scrollView.contentInsetAdjustmentBehavior = .never
            }
            // The edge effect blurs and tints the page under bars, which
            // shows as a band of another color behind the floating controls.
            scrollView.topEdgeEffect.isHidden = true
            scrollView.bottomEdgeEffect.isHidden = true
        }
    }
}

private extension UIView {
    func descendants<T: UIView>(of type: T.Type) -> [T] {
        subviews.flatMap { subview in
            (subview as? T).map { [$0] } ?? [] + subview.descendants(of: type)
        }
    }
}

/// A picture of a page, shown while it turns.
private final class SnapshotPageController: UIViewController {
    let position: BookPosition
    private let imageView = UIImageView()
    private weak var navigator: WebNavigator?
    private(set) var image: CGImage?

    init(position: BookPosition, image: CGImage?, navigator: WebNavigator) {
        self.position = position
        self.image = image
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // An opaque page, so the curl has a page to lift. The picture
        // carries the theme's own color when it arrives.
        view.backgroundColor = navigator?.pageColor ?? .systemBackground
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleToFill
        view.addSubview(imageView)
        if let image {
            show(image)
        } else {
            Task { [weak self] in
                guard let self, let image = await navigator?.snapshot(of: position) else { return }
                show(image)
            }
        }
    }

    private func show(_ image: CGImage) {
        self.image = image
        let scale = view.window?.windowScene?.screen.scale ?? traitCollection.displayScale
        imageView.image = UIImage(cgImage: image, scale: scale, orientation: .up)
        if let corner = image.cornerColor {
            view.backgroundColor = corner
        }
    }
}

extension CGImage {
    /// The color of the top-leading pixel, which is the page's background.
    var cornerColor: UIColor? {
        guard let data = dataProvider?.data, let bytes = CFDataGetBytePtr(data), bitsPerPixel >= 24 else { return nil }
        let order = bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let first = CGFloat(bytes[0]) / 255, second = CGFloat(bytes[1]) / 255, third = CGFloat(bytes[2]) / 255
        // Little-endian 32-bit images store blue first.
        return order == CGBitmapInfo.byteOrder32Little.rawValue
            ? UIColor(red: third, green: second, blue: first, alpha: 1)
            : UIColor(red: first, green: second, blue: third, alpha: 1)
    }
}
#endif
