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
    @Environment(\.readerEdgePages) private var edgePages

    func makeUIViewController(context: Context) -> ImagePagerController {
        ImagePagerController(navigator: navigator, edgePages: edgePages)
    }

    func updateUIViewController(_ controller: ImagePagerController, context: Context) {
        controller.setEdgePages(edgePages)
    }
}

/// The page view controller and the pages it turns.
final class ImagePagerController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, ImagePaging {
    private let navigator: ImageNavigator
    private let isCurl: Bool
    /// The pages the app gave the publication's ends, if any.
    private var edgePages: ReaderEdgePages?
    /// Kept, since a gesture recognizer doesn't keep its target.
    private var pastEndSwipe: PastEndSwipe?
    private var pastStartSwipe: PastEndSwipe?

    /// A page the pager can show: one of the comic's (the first of a
    /// spread), or one outside them.
    enum Slot: Hashable {
        case page(Int)
        case outside(OutsidePlace)
    }

    init(navigator: ImageNavigator, edgePages: ReaderEdgePages?) {
        self.navigator = navigator
        self.edgePages = edgePages
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
        setViewControllers(pages(for: .page(spreadStart(of: navigator.index ?? 0))), direction: .forward, animated: false)
        navigator.pager = self
        // With pages for the ends, the turn past one is a turn onto the
        // page past it. Without, a swipe the pager has no page for is
        // still a turn past the end.
        pastEndSwipe = PastEndSwipe(in: view, isRightToLeft: navigator.isRightToLeft) { [weak self] in
            guard let self else { return false }
            return isAtBoundary(.end)
        } didSwipe: { [weak self] in
            self?.navigator.didTurnPastEnd()
        }
        // The swipe back is the swipe on, mirrored.
        pastStartSwipe = PastEndSwipe(in: view, isRightToLeft: !navigator.isRightToLeft) { [weak self] in
            guard let self else { return false }
            return isAtBoundary(.start)
        } didSwipe: { [weak self] in
            self?.navigator.didTurnPastStart()
        }
    }

    /// Whether a swipe toward `edge` has no page to turn to.
    private func isAtBoundary(_ edge: ReaderEdge) -> Bool {
        switch currentSlot {
        case .page(let index):
            // A zoomed page pans to look around it, which isn't a turn.
            guard edgePages?.has(edge) != true,
                  let page = viewControllers?.first as? ImagePageController, !page.isZoomed
            else { return false }
            return edge == .end ? startAfter(index) == nil : startBefore(index) == nil
        case .outside(let place):
            return place == .past(edge)
        case nil:
            return false
        }
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
        if changed, case .page = currentSlot {
            setViewControllers([first], direction: .forward, animated: false)
        }
    }

    fileprivate var navigatorForPages: ImageNavigator { navigator }

    private var currentIndex: Int? {
        (viewControllers?.first as? ImagePageController)?.index
    }

    private var currentSlot: Slot? {
        viewControllers?.first.flatMap(slot(of:))
    }

    /// Whether two pages show side by side, as an open book does: on a
    /// screen wider than it is tall, where one page would sit narrow
    /// between wide black margins. The cover stays alone, so the pairs
    /// after it are the ones the artist drew to face each other.
    private(set) var isSpread = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        var wide = view.bounds.width > view.bounds.height
        #if DEBUG
        // Simulators can't always be turned, so a debug run can ask for
        // spreads outright.
        if ProcessInfo.processInfo.environment["CHEK_READER_SPREADS"] == "1" {
            wide = true
        }
        #endif
        guard wide != isSpread else { return }
        isSpread = wide
        // Turning the device regroups the pages, keeping the one in view.
        if let currentIndex {
            setViewControllers(pages(for: .page(spreadStart(of: currentIndex))), direction: .forward, animated: false)
        }
    }

    /// The first page of the spread `page` is in.
    private func spreadStart(of page: Int) -> Int {
        guard isSpread, page > 0 else { return page }
        return page.isMultiple(of: 2) ? page - 1 : page
    }

    /// The page shown beside `start`, if any.
    private func spreadPartner(of start: Int) -> Int? {
        guard isSpread, start > 0, start + 1 < navigator.pageCount else { return nil }
        return start + 1
    }

    private func startAfter(_ start: Int) -> Int? {
        let next = isSpread && start > 0 ? start + 2 : start + 1
        return next < navigator.pageCount ? next : nil
    }

    private func startBefore(_ start: Int) -> Int? {
        guard start > 0 else { return nil }
        return isSpread ? max(start - 2, 0) : start - 1
    }

    /// The slot a turn goes to from `slot`, if any.
    private func slot(from slot: Slot, forward: Bool) -> Slot? {
        switch slot {
        case .page(let index):
            if let next = forward ? startAfter(index) : startBefore(index) {
                return .page(next)
            }
            let edge: ReaderEdge = forward ? .end : .start
            return edgePages?.has(edge) == true ? .outside(.edge(edge)) : nil
        case .outside(let place):
            if place.isInside(afterTurning: forward) {
                return .page(place.edge == .end ? spreadStart(of: navigator.pageCount - 1) : 0)
            }
            return place.turned(forward: forward).map(Slot.outside)
        }
    }

    /// Whether `slot` comes after `other` in reading.
    private func isAfter(_ slot: Slot, _ other: Slot?) -> Bool {
        func rank(_ slot: Slot?) -> Int {
            switch slot {
            case .outside(.past(.start)): -2
            case .outside(.edge(.start)): -1
            case .page(let index): index
            case .outside(.edge(.end)): Int.max - 1
            case .outside(.past(.end)): Int.max
            case nil: 0
            }
        }
        return rank(slot) > rank(other)
    }

    // MARK: - ImagePaging

    func display(page: Int, animated: Bool) {
        show(.page(spreadStart(of: page)), animated: animated)
    }

    func turnOutside(forward: Bool) -> Bool {
        guard let current = currentSlot else { return false }
        switch current {
        case .page:
            // Only from the last page on, or the first back.
            guard case .outside? = slot(from: current, forward: forward) else { return false }
        case .outside:
            break
        }
        guard let target = slot(from: current, forward: forward) else { return false }
        show(target, animated: true)
        return true
    }

    /// Shows `target`, turning to it when `animated`, and says where it is
    /// once it's there.
    private func show(_ target: Slot, animated: Bool) {
        guard target != currentSlot else { return }
        let forward = isAfter(target, currentSlot)
        let animate = animated && !UIAccessibility.isReduceMotionEnabled
        setViewControllers(pages(for: target, animated: animate), direction: forward ? .forward : .reverse, animated: animate) { [weak self] _ in
            // Comic pages are recorded as they're asked for; the other
            // places once they're on screen, as after a swipe.
            if case .outside = target {
                self?.didSettle(on: target)
            } else {
                self?.navigator.didShowEdge(nil)
            }
        }
    }

    /// Tells the navigator where a turn left the pager.
    private func didSettle(on slot: Slot) {
        switch slot {
        case .page(let index):
            navigator.didShow(index)
            navigator.didShowEdge(nil)
        case .outside(.edge(let edge)):
            navigator.didShowEdge(edge)
        case .outside(.past(let edge)):
            navigator.didShowEdge(edge)
            if edge == .end {
                navigator.didTurnPastEnd()
            } else {
                navigator.didTurnPastStart()
            }
        }
    }

    // MARK: - Data source

    private func page(at start: Int) -> ImagePageController {
        ImagePageController(index: start, partner: spreadPartner(of: start), pager: self)
    }

    private func front(for slot: Slot) -> UIViewController {
        switch slot {
        case .page(let start):
            return page(at: start)
        case .outside(.edge(let edge)):
            return EdgePageController(edge: edge, content: edgePages?.content(edge) ?? AnyView(EmptyView()), pageColor: .black)
        case .outside(.past(let edge)):
            return PastEdgePageController(edge: edge, pageColor: .black)
        }
    }

    private func slot(of viewController: UIViewController) -> Slot? {
        switch viewController {
        case let page as ImagePageController: .page(page.index)
        case let edge as EdgePageController: .outside(.edge(edge.edge))
        case let past as PastEdgePageController: .outside(.past(past.edge))
        default: nil
        }
    }

    /// The pages to set for `slot`. With a spine at the edge, UIKit takes
    /// the front alone, and asks the data source for its back.
    private func pages(for slot: Slot, animated: Bool = false) -> [UIViewController] {
        let front = front(for: slot)
        // A double-sided curl takes the back too, but only when animated.
        return isCurl && animated ? [front, back(of: slot)] : [front]
    }

    private func back(of slot: Slot) -> PageBackController {
        let back = PageBackController(front: slot, image: nil, pageColor: .black)
        // A spread's back would be two pages too; plain black reads as a
        // page's reverse well enough, as it does for the ends' pages.
        if case .page(let index) = slot, !isSpread {
            Task { [weak back, navigator] in
                let image = await navigator.image(at: index)
                back?.setImage(image.map { UIImage(cgImage: $0) })
            }
        }
        return back
    }

    // With a curl, every front is followed by its back.

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        if let back = viewController as? PageBackController, let slot = back.front.base as? Slot {
            return front(for: slot)
        }
        guard let current = slot(of: viewController), let previous = slot(from: current, forward: false) else { return nil }
        return isCurl ? back(of: previous) : front(for: previous)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        if isCurl, let current = slot(of: viewController) {
            return back(of: current)
        }
        let current = (viewController as? PageBackController)?.front.base as? Slot ?? slot(of: viewController)
        guard let current, let next = slot(from: current, forward: true) else { return nil }
        return front(for: next)
    }

    // MARK: - Delegate

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let currentSlot else { return }
        didSettle(on: currentSlot)
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

/// One page, or two side by side, zoomable as one.
private final class ImagePageController: UIViewController, UIScrollViewDelegate {
    let index: Int
    /// The page shown beside this one in a spread.
    let partner: Int?
    private weak var pager: ImagePagerController?
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let failure = PageFailureView()
    /// Whether the sharper image for zooming has been asked for.
    private var requestedZoomImage = false
    /// A tall page starts at its top, once.
    private var hasPlacedTallPage = false

    init(index: Int, partner: Int? = nil, pager: ImagePagerController) {
        self.index = index
        self.partner = partner
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
        scrollView.topEdgeEffect.isHidden = true
        scrollView.bottomEdgeEffect.isHidden = true
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
        accessibilityLabel = partner.map { String(localized: "Pages \(index + 1) and \($0 + 1)", bundle: .module) }
            ?? String(localized: "Page \(index + 1)", bundle: .module)

        failure.frame = view.bounds
        failure.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        failure.retry = { [weak self] in self?.loadImage() }
        view.addSubview(failure)

        loadImage()
    }

    private func loadImage() {
        failure.isHidden = true
        spinner.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            guard var image = await pager?.image(at: index) else {
                spinner.stopAnimating()
                failure.isHidden = false
                return
            }
            if let partner, let second = await pager?.image(at: partner) {
                // The two pages drawn as one, so zooming and panning treat
                // the spread as the single picture it reads as. Right to
                // left, the earlier page is on the right.
                let rightToLeft = pager?.navigatorForPages.isRightToLeft ?? false
                image = await PageSpread.compose(left: rightToLeft ? second : image, right: rightToLeft ? image : second) ?? image
                // The sharper zoom image is per page; the spread keeps
                // what it has.
                requestedZoomImage = true
            }
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

    var isZoomed: Bool {
        scrollView.zoomScale > 1.01
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        // A zoomed page is being looked at closely; taps don't turn it.
        guard scrollView.zoomScale <= 1.01 else { return }
        pager?.tapped(at: recognizer.location(in: view), in: view.bounds.width)
    }
}
#endif
