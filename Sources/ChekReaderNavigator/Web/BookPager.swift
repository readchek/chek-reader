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
        BookPagerController(navigator: navigator, live: UIHostingController(rootView: content()))
    }

    func updateUIViewController(_ controller: BookPagerController<Content>, context: Context) {
        controller.live.rootView = content()
    }
}

final class BookPagerController<Content: View>: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, BookPaging {
    private let navigator: WebNavigator
    let live: UIHostingController<Content>
    private lazy var liveController = LivePageController(hosting: live)
    /// The turn waiting for the web content to catch up, so a new one
    /// doesn't start from a stale page.
    private var settling: Task<Void, Never>?

    init(navigator: WebNavigator, live: UIHostingController<Content>) {
        self.navigator = navigator
        self.live = live
        let curl = navigator.pageTransition == .curl
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
        setViewControllers([liveController], direction: .forward, animated: false)
        navigator.pager = self
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
            setViewControllers([page], direction: forward ? .forward : .reverse, animated: animate) { _ in
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
            setViewControllers([liveController], direction: .forward, animated: false)
        }
    }

    // MARK: - Data source

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let here = position(of: viewController), let target = navigator.position(before: here) else { return nil }
        return snapshotPage(at: target)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let here = position(of: viewController), let target = navigator.position(after: here) else { return nil }
        return snapshotPage(at: target)
    }

    private func position(of viewController: UIViewController) -> BookPosition? {
        if let page = viewController as? SnapshotPageController {
            return page.position
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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The web views must not pan between columns themselves, or their
        // scrolling takes the drag from the page turn.
        for scrollView in view.descendants(of: UIScrollView.self) where scrollView.isScrollEnabled {
            scrollView.isScrollEnabled = false
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
    private var image: CGImage?

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
        view.backgroundColor = .systemBackground
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
        let scale = view.window?.windowScene?.screen.scale ?? traitCollection.displayScale
        imageView.image = UIImage(cgImage: image, scale: scale, orientation: .up)
        if let corner = image.cornerColor {
            view.backgroundColor = corner
        }
    }
}

private extension CGImage {
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
