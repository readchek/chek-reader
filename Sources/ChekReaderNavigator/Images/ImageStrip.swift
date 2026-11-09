#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import UIKit

/// Shows a comic's pages in one continuous column, scrolled vertically, as
/// webtoons are read. Each page is as wide as the screen.
struct ImageStripView: UIViewControllerRepresentable {
    let navigator: ImageNavigator
    @Environment(\.readerEdgePages) private var edgePages

    func makeUIViewController(context: Context) -> ImageStripController {
        ImageStripController(navigator: navigator, edgePages: edgePages)
    }

    func updateUIViewController(_ controller: ImageStripController, context: Context) {
        controller.setEdgePages(edgePages)
    }
}

final class ImageStripController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate, ImagePaging {
    private let navigator: ImageNavigator
    private var collectionView: UICollectionView!
    /// The pages the app gave the comic's ends, if any. They sit in the
    /// column before the first page and after the last, a screen tall.
    private var edgePages: ReaderEdgePages?
    /// Height over width of each page once it's decoded. Pages not yet
    /// decoded are drawn at a typical webtoon proportion until they are.
    private var aspects: [Int: CGFloat] = [:]
    private static let assumedAspect: CGFloat = 1.6
    /// The page the column is scrolled to, as last reported.
    private var reportedIndex: Int?
    /// The end whose page is showing, as last reported.
    private var reportedEdge: ReaderEdge?
    private var hasPlacedStart = false
    /// A tap scroll is running, which counts as reading like a drag does.
    private var isAnimatingTap = false

    /// The column's sections: the start's page, the comic's, the end's.
    private enum Section: Int, CaseIterable {
        case start, pages, end
    }

    init(navigator: ImageNavigator, edgePages: ReaderEdgePages?) {
        self.navigator = navigator
        self.edgePages = edgePages
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .black
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.showsVerticalScrollIndicator = false
        // No blur or tint under the reader's floating controls.
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(ImageStripCell.self, forCellWithReuseIdentifier: ImageStripCell.identifier)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Self.edgeIdentifier)
        view.addSubview(collectionView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)
        navigator.pager = self
    }

    private static let edgeIdentifier = "ImageStripEdge"

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The column can lay out before the navigator knows where you are;
        // it places itself once it does.
        guard !hasPlacedStart, collectionView.bounds.width > 0, let index = navigator.index else { return }
        reportedIndex = index
        // At the page, past the start's own page above it. The last page
        // ends at the screen's foot, with the end's own page below it
        // rather than in its place, as reading back into a chapter arrives.
        if index > 0 || hasPage(.start) {
            collectionView.layoutIfNeeded()
            let isLast = index == navigator.pageCount - 1 && hasPage(.end)
            collectionView.scrollToItem(at: pageIndexPath(index), at: isLast ? .bottom : .top, animated: false)
        }
        // Scrolling before this is the column settling, not reading, and
        // would otherwise record the first page as where you are.
        hasPlacedStart = true
    }

    private func pageIndexPath(_ page: Int) -> IndexPath {
        IndexPath(item: page, section: Section.pages.rawValue)
    }

    private func hasPage(_ edge: ReaderEdge) -> Bool {
        edgePages?.has(edge) == true
    }

    /// Takes new pages for the ends, as the app learns what's either side.
    /// The start's page coming or going keeps the page you're on in place.
    func setEdgePages(_ pages: ReaderEdgePages?) {
        let old = edgePages
        edgePages = pages
        guard isViewLoaded else { return }
        let hadStart = old?.has(.start) == true, hasStart = pages?.has(.start) == true
        let hadEnd = old?.has(.end) == true, hasEnd = pages?.has(.end) == true
        UIView.performWithoutAnimation {
            let shift = view.bounds.height * (hasStart ? 1 : 0) - view.bounds.height * (hadStart ? 1 : 0)
            if hadStart != hasStart || hadEnd != hasEnd {
                collectionView.reloadSections(IndexSet([Section.start.rawValue, Section.end.rawValue]))
                collectionView.layoutIfNeeded()
                if shift != 0, hasPlacedStart {
                    collectionView.contentOffset.y = max(collectionView.contentOffset.y + shift, 0)
                }
            } else {
                // The same pages with what they say brought up to date.
                for cell in collectionView.visibleCells {
                    if let edgeCell = EdgeCell(cell) {
                        edgeCell.show(pages?.content(edgeCell.edge))
                    }
                }
            }
        }
    }

    // MARK: - ImagePaging

    func display(page: Int, animated: Bool) {
        guard page >= 0, page < navigator.pageCount, page != reportedIndex || reportedEdge != nil else { return }
        guard hasPlacedStart else {
            view.setNeedsLayout()
            return
        }
        reportedIndex = page
        collectionView.scrollToItem(at: pageIndexPath(page), at: .top, animated: animated && !UIAccessibility.isReduceMotionEnabled)
        report(edge: nil)
    }

    /// Records which end's page is showing, when it changes.
    private func report(edge: ReaderEdge?) {
        guard edge != reportedEdge else { return }
        reportedEdge = edge
        navigator.didShowEdge(edge)
    }

    /// From an end's own page, a turn scrolls on or back as a tap does, and
    /// on past it goes through to what's next.
    func turnOutside(forward: Bool) -> Bool {
        guard reportedEdge == nil else {
            step(forward: forward)
            return true
        }
        // From the last page on, or the first back, onto the end's page.
        let edge: ReaderEdge = forward ? .end : .start
        guard hasPage(edge), navigator.index == (forward ? navigator.pageCount - 1 : 0) else { return false }
        let section = forward ? Section.end : Section.start
        collectionView.scrollToItem(at: IndexPath(item: 0, section: section.rawValue), at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
        report(edge: edge)
        return true
    }

    // MARK: - Data source

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        Section.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .start: hasPage(.start) ? 1 : 0
        case .end: hasPage(.end) ? 1 : 0
        case .pages: navigator.pageCount
        case nil: 0
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let edge = edge(of: indexPath.section) {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.edgeIdentifier, for: indexPath)
            let edgeCell = EdgeCell(cell: cell, edge: edge)
            edgeCell.show(edgePages?.content(edge))
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageStripCell.identifier, for: indexPath) as! ImageStripCell
        let index = indexPath.item
        cell.show(index: index) { [weak self] in
            await self?.loadImage(at: index)
        }
        return cell
    }

    private func edge(of section: Int) -> ReaderEdge? {
        switch Section(rawValue: section) {
        case .start: .start
        case .end: .end
        case .pages, nil: nil
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths where indexPath.section == Section.pages.rawValue {
            Task { _ = await loadImage(at: indexPath.item) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        // An end's page is a screen, as the pages turned one at a time are.
        if edge(of: indexPath.section) != nil {
            return CGSize(width: width, height: collectionView.bounds.height)
        }
        return CGSize(width: width, height: (width * (aspects[indexPath.item] ?? Self.assumedAspect)).rounded())
    }

    /// Decodes a page and, the first time, sizes its cell to the page,
    /// keeping whatever is on screen where it is.
    private func loadImage(at index: Int) async -> UIImage? {
        guard let cgImage = await navigator.image(at: index), cgImage.width > 0 else { return nil }
        let aspect = CGFloat(cgImage.height) / CGFloat(cgImage.width)
        if abs((aspects[index] ?? Self.assumedAspect) - aspect) > 0.001 {
            let width = collectionView.bounds.width
            let change = width * (aspect - (aspects[index] ?? Self.assumedAspect))
            let visible = collectionView.indexPathsForVisibleItems
            // The start's page above counts as above every page.
            let top = visible.contains { $0.section == Section.start.rawValue }
                ? -1
                : visible.filter { $0.section == Section.pages.rawValue }.map(\.item).min() ?? 0
            aspects[index] = aspect
            UIView.performWithoutAnimation {
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.layoutIfNeeded()
                // A page above the screen growing would push the reader down.
                if index < top {
                    collectionView.contentOffset.y += change
                }
            }
        }
        let scale = view.window?.windowScene?.screen.scale ?? traitCollection.displayScale
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    // MARK: - Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard hasPlacedStart, scrollView.isTracking || scrollView.isDecelerating || isAnimatingTap else { return }
        let edge = shownEdge(in: scrollView)
        report(edge: edge)
        guard edge == nil else { return }
        // The page at the upper third of the screen is the one being read.
        let probe = CGPoint(x: scrollView.bounds.midX, y: scrollView.contentOffset.y + scrollView.bounds.height / 3)
        guard let indexPath = collectionView.indexPathForItem(at: probe), indexPath.section == Section.pages.rawValue,
              indexPath.item != reportedIndex
        else { return }
        reportedIndex = indexPath.item
        navigator.didShow(indexPath.item)
    }

    /// The end whose page covers most of the screen, if either does.
    private func shownEdge(in scrollView: UIScrollView) -> ReaderEdge? {
        let middle = scrollView.contentOffset.y + scrollView.bounds.height / 2
        if hasPage(.start),
           let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: Section.start.rawValue))?.frame,
           frame.maxY > middle {
            return .start
        }
        if hasPage(.end),
           let frame = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: Section.end.rawValue))?.frame,
           frame.minY < middle {
            return .end
        }
        return nil
    }

    /// Pulling the strip up past its end, as at the bottom of a webtoon
    /// episode, asks to go on to what comes next. With a page of its own
    /// at the end, that's pulling on past the page, when reading goes
    /// through it.
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let end = max(scrollView.contentSize.height, scrollView.bounds.height)
        if scrollView.contentOffset.y + scrollView.bounds.height - end > 80 {
            goPast(.end)
        } else if scrollView.contentOffset.y < -80 {
            // And down past its start, to go back into what came before.
            goPast(.start)
        }
    }

    /// Counts a turn past `edge`, unless its page is where reading stops.
    private func goPast(_ edge: ReaderEdge) {
        guard (edgePages?.page(at: edge) ?? .none).countsTurnsPast else { return }
        if edge == .end {
            navigator.didTurnPastEnd()
        } else {
            navigator.didTurnPastStart()
        }
    }

    /// Taps on an end's own page are the app's.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let indexPath = collectionView.indexPathForItem(at: touch.location(in: collectionView)) else { return true }
        return edge(of: indexPath.section) == nil
    }

    /// A tap in the middle shows the controls; one near the top or bottom
    /// scrolls back or on by most of a screen.
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let y = recognizer.location(in: view).y / max(view.bounds.height, 1)
        let x = recognizer.location(in: view).x / max(view.bounds.width, 1)
        let forward = y > 0.75 || x > 0.75
        let backward = y < 0.25 || x < 0.25
        guard forward != backward else {
            navigator.handle(.tap(.center))
            return
        }
        step(forward: forward)
    }

    /// Scrolls on or back by most of a screen, or past the end when it's
    /// already in view.
    private func step(forward: Bool) {
        let distance = collectionView.bounds.height * 0.85 * (forward ? 1 : -1)
        let maxOffset = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
        let target = min(max(collectionView.contentOffset.y + distance, 0), maxOffset)
        if forward, collectionView.contentOffset.y >= maxOffset - 1 {
            goPast(.end)
            return
        }
        if !forward, collectionView.contentOffset.y <= 1 {
            goPast(.start)
            return
        }
        isAnimatingTap = true
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.collectionView.contentOffset.y = target
        } completion: { _ in
            self.scrollViewDidScroll(self.collectionView)
            self.isAnimatingTap = false
        }
    }
}

/// A cell showing an end's own page, hosting what the app gave it.
@MainActor
private struct EdgeCell {
    let cell: UICollectionViewCell
    let edge: ReaderEdge

    init(cell: UICollectionViewCell, edge: ReaderEdge) {
        self.cell = cell
        self.edge = edge
        cell.tag = edge == .start ? 1 : 2
    }

    init?(_ cell: UICollectionViewCell) {
        guard cell.tag == 1 || cell.tag == 2 else { return nil }
        self.init(cell: cell, edge: cell.tag == 1 ? .start : .end)
    }

    func show(_ content: AnyView?) {
        cell.backgroundColor = .black
        cell.contentConfiguration = UIHostingConfiguration { content ?? AnyView(EmptyView()) }
            .margins(.all, 0)
    }
}

private final class ImageStripCell: UICollectionViewCell {
    static let identifier = "ImageStripCell"
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let failure = PageFailureView()
    private var loading: Task<Void, Never>?
    private var index: Int?
    private var load: (@MainActor () async -> UIImage?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        imageView.contentMode = .scaleToFill
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        failure.frame = contentView.bounds
        failure.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        failure.retry = { [weak self] in self?.start() }
        contentView.addSubview(failure)
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        imageView.image = nil
        index = nil
        load = nil
        failure.isHidden = true
    }

    func show(index: Int, load: @escaping @MainActor () async -> UIImage?) {
        self.index = index
        self.load = load
        accessibilityLabel = String(localized: "Page \(index + 1)", bundle: .module)
        start()
    }

    private func start() {
        guard let index, let load else { return }
        failure.isHidden = true
        spinner.startAnimating()
        loading?.cancel()
        loading = Task { [weak self] in
            let image = await load()
            guard let self, !Task.isCancelled, self.index == index else { return }
            spinner.stopAnimating()
            imageView.image = image
            failure.isHidden = image != nil
        }
    }
}
#endif
