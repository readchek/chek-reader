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

    func makeUIViewController(context: Context) -> BookPagerController<Content> {
        let hosting = UIHostingController(rootView: content())
        // The page is laid out once for the screen. Bars and the status bar
        // coming and going must not change its safe area and move the text.
        hosting.safeAreaRegions = []
        return BookPagerController(navigator: navigator, live: hosting)
    }

    func updateUIViewController(_ controller: BookPagerController<Content>, context: Context) {
        controller.live.rootView = content()
    }
}

final class BookPagerController<Content: View>: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, BookPaging {
    private let navigator: WebNavigator
    let live: UIHostingController<Content>
    private lazy var liveController = LivePageController(hosting: live)
    private let isCurl: Bool
    /// The turn waiting for the web content to catch up, so a new one
    /// doesn't start from a stale page.
    private var settling: Task<Void, Never>?

    init(navigator: WebNavigator, live: UIHostingController<Content>) {
        self.navigator = navigator
        self.live = live
        let curl = navigator.pageTransition == .curl
        isCurl = curl
        super.init(
            transitionStyle: curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: curl ? [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)] : [.interPageSpacing: NSNumber(value: 0)]
        )
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
        isDoubleSided = isCurl
        setViewControllers(pages(for: liveController), direction: .forward, animated: false)
        navigator.pager = self
    }

    /// `front`, and its back when pages curl.
    private func pages(for front: UIViewController) -> [UIViewController] {
        guard isCurl, let position = position(of: front) else { return [front] }
        return [front, back(of: position, front: front)]
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
            setViewControllers(pages(for: page), direction: forward ? .forward : .reverse, animated: animate) { _ in
                continuation.resume()
            }
        }
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
        if let back = viewController as? PageBackController, let position = back.front.base as? BookPosition {
            return snapshotPage(at: position)
        }
        guard let here = position(of: viewController), let target = navigator.position(before: here) else { return nil }
        let front = snapshotPage(at: target)
        return isCurl ? back(of: target, front: front) : front
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if isCurl, !(viewController is PageBackController), let here = position(of: viewController) {
            return back(of: here, front: viewController)
        }
        let here = (viewController as? PageBackController)?.front.base as? BookPosition ?? position(of: viewController)
        guard let here, let target = navigator.position(after: here) else { return nil }
        return snapshotPage(at: target)
    }

    private func position(of viewController: UIViewController) -> BookPosition? {
        if let page = viewController as? SnapshotPageController {
            return page.position
        }
        if viewController is PageBackController {
            return nil
        }
        return navigator.position
    }

    private func snapshotPage(at position: BookPosition) -> SnapshotPageController {
        SnapshotPageController(position: position, image: nil, navigator: navigator)
    }

    // MARK: - Delegate

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let page = viewControllers?.first as? SnapshotPageController else { return }
        settle(on: page.position)
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
