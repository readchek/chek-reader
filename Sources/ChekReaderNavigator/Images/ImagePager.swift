#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import UIKit

/// Turns a comic's pages with `UIPageViewController`, so a turn follows
/// your finger with the system's own physics: a page curl or a slide.
///
/// Each page zooms on its own, with pinch and double tap, and pages run
/// right to left when the publication does.
struct ImagePagerView: UIViewControllerRepresentable {
    let navigator: ImageNavigator

    func makeUIViewController(context: Context) -> ImagePagerController {
        ImagePagerController(navigator: navigator)
    }

    func updateUIViewController(_ controller: ImagePagerController, context: Context) {}
}

/// The page view controller and the pages it turns.
final class ImagePagerController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, ImagePaging {
    private let navigator: ImageNavigator
    private let isCurl: Bool

    init(navigator: ImageNavigator) {
        self.navigator = navigator
        let curl = navigator.pageTransition == .curl
        isCurl = curl
        super.init(
            transitionStyle: curl ? .pageCurl : .scroll,
            navigationOrientation: .horizontal,
            options: curl ? [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)] : [.interPageSpacing: NSNumber(value: 12)]
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
        view.backgroundColor = .black
        dataSource = self
        delegate = self
        // A right-to-left comic curls from the left edge, as a manga does.
        view.semanticContentAttribute = navigator.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
        // The curl adds its own taps at the edges; the pages handle taps so
        // the middle can show the reader's controls instead.
        for recognizer in gestureRecognizers where recognizer is UITapGestureRecognizer {
            recognizer.isEnabled = false
        }
        setViewControllers(pages(for: navigator.index ?? 0), direction: .forward, animated: false)
        navigator.pager = self
    }

    private var currentIndex: Int? {
        (viewControllers?.first as? ImagePageController)?.index
    }

    // MARK: - ImagePaging

    func display(page: Int, animated: Bool) {
        guard page != currentIndex else { return }
        let forward = page > (currentIndex ?? 0)
        let animate = animated && !UIAccessibility.isReduceMotionEnabled
        setViewControllers(
            pages(for: page, animated: animate),
            direction: forward ? .forward : .reverse,
            animated: animate
        )
    }

    // MARK: - Data source

    /// The pages to set for `index`. With a spine at the edge, UIKit takes
    /// the front alone, and asks the data source for its back.
    private func pages(for index: Int, animated: Bool = false) -> [UIViewController] {
        let front = ImagePageController(index: index, pager: self)
        // A double-sided curl takes the back too, but only when animated.
        return isCurl && animated ? [front, back(of: index)] : [front]
    }

    private func back(of index: Int) -> PageBackController {
        let back = PageBackController(front: index, image: nil, pageColor: .black)
        Task { [weak back, navigator] in
            let image = await navigator.image(at: index)
            back?.setImage(image.map { UIImage(cgImage: $0) })
        }
        return back
    }

    // With a curl, every front is followed by its back.

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if let back = viewController as? PageBackController, let index = back.front.base as? Int {
            return ImagePageController(index: index, pager: self)
        }
        guard let page = viewController as? ImagePageController, page.index > 0 else { return nil }
        return isCurl ? back(of: page.index - 1) : ImagePageController(index: page.index - 1, pager: self)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if isCurl, let page = viewController as? ImagePageController {
            return back(of: page.index)
        }
        let index = (viewController as? PageBackController)?.front.base as? Int ?? (viewController as? ImagePageController)?.index
        guard let index, index + 1 < navigator.pageCount else { return nil }
        return ImagePageController(index: index + 1, pager: self)
    }

    // MARK: - Delegate

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let currentIndex else { return }
        navigator.didShow(currentIndex)
    }

    // MARK: - Pages

    fileprivate func image(at index: Int) async -> CGImage? {
        await navigator.image(at: index)
    }

    fileprivate func zoomedImage(at index: Int, maxPixelSize: Int) async -> CGImage? {
        await navigator.image(at: index, maxPixelSize: maxPixelSize)
    }

    /// Turns for a tap at the side, or shows the controls for one in the middle.
    fileprivate func tapped(at point: CGPoint, in width: CGFloat) {
        let x = point.x / max(width, 1)
        let zone: PageCommand.Input.Zone = x < 0.3 ? .left : x > 0.7 ? .right : .center
        navigator.handle(.tap(zone))
    }
}

/// One page, zoomable on its own.
private final class ImagePageController: UIViewController, UIScrollViewDelegate {
    let index: Int
    private weak var pager: ImagePagerController?
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    /// Whether the sharper image for zooming has been asked for.
    private var requestedZoomImage = false
    /// A tall page starts at its top, once.
    private var hasPlacedTallPage = false

    init(index: Int, pager: ImagePagerController) {
        self.index = index
        self.pager = pager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIgnoresInvertColors = true
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(tap)

        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = String(localized: "Page \(index + 1)", bundle: .module)

        spinner.startAnimating()
        Task { [weak self] in
            guard let self, let image = await pager?.image(at: index) else { return }
            show(image)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale == 1 {
            layoutImage()
        }
    }

    private func show(_ cgImage: CGImage) {
        spinner.stopAnimating()
        let scale = view.window?.windowScene?.screen.scale ?? traitCollection.displayScale
        UIView.transition(with: imageView, duration: 0.15, options: .transitionCrossDissolve) {
            self.imageView.image = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        }
        layoutImage()
    }

    /// Fits the page in the view at zoom 1, centered.
    private func layoutImage() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = scrollView.bounds
            return
        }
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0 else { return }
        // A page much taller than the screen, such as a webtoon strip, fits
        // the width and scrolls down; shrinking it to fit the height would
        // leave it too narrow to read.
        let isTall = image.size.height / image.size.width > bounds.height / bounds.width * 1.15
        let fit = isTall
            ? bounds.width / image.size.width
            : min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        imageView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        scrollView.alwaysBounceVertical = isTall
        centerImage()
        if isTall, !hasPlacedTallPage {
            hasPlacedTallPage = true
            scrollView.contentOffset = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        }
    }

    private func centerImage() {
        let bounds = scrollView.bounds.size
        let content = imageView.frame.size
        scrollView.contentInset = UIEdgeInsets(
            top: max(0, (bounds.height - content.height) / 2),
            left: max(0, (bounds.width - content.width) / 2),
            bottom: 0,
            right: 0
        )
    }

    // MARK: - Zoom

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        // Pages decode to the screen's size, which blurs when zoomed, so a
        // sharper copy is fetched the first time the page is zoomed in.
        guard scrollView.zoomScale > 1.2, !requestedZoomImage else { return }
        requestedZoomImage = true
        let pixels = Int(max(view.bounds.width, view.bounds.height) * traitCollection.displayScale * scrollView.maximumZoomScale)
        Task { [weak self] in
            guard let self, let sharper = await pager?.zoomedImage(at: index, maxPixelSize: min(pixels, 8192)) else { return }
            let scale = imageView.image?.scale ?? traitCollection.displayScale
            let fitted = imageView.image?.size ?? .zero
            // The same page drawn at more pixels, so the view's size stays.
            let factor = CGFloat(sharper.width) / max(fitted.width * scale, 1)
            imageView.image = UIImage(cgImage: sharper, scale: scale * factor, orientation: .up)
        }
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1 {
            scrollView.setZoomScale(1, animated: true)
            return
        }
        let point = recognizer.location(in: imageView)
        let scale: CGFloat = 2.5
        let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        // A zoomed page is being looked at closely; taps don't turn it.
        guard scrollView.zoomScale <= 1.01 else { return }
        pager?.tapped(at: recognizer.location(in: view), in: view.bounds.width)
    }
}
#endif
