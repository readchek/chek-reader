#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import UIKit

/// Shows a comic's pages in one continuous column, scrolled vertically, as
/// webtoons are read. Each page is as wide as the screen.
struct ImageStripView: UIViewControllerRepresentable {
    let navigator: ImageNavigator

    func makeUIViewController(context: Context) -> ImageStripController {
        ImageStripController(navigator: navigator)
    }

    func updateUIViewController(_ controller: ImageStripController, context: Context) {}
}

final class ImageStripController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching, ImagePaging {
    private let navigator: ImageNavigator
    private var collectionView: UICollectionView!
    /// Height over width of each page once it's decoded. Pages not yet
    /// decoded are drawn at a typical webtoon proportion until they are.
    private var aspects: [Int: CGFloat] = [:]
    private static let assumedAspect: CGFloat = 1.6
    /// The page the column is scrolled to, as last reported.
    private var reportedIndex: Int?
    private var hasPlacedStart = false

    init(navigator: ImageNavigator) {
        self.navigator = navigator
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
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(ImageStripCell.self, forCellWithReuseIdentifier: ImageStripCell.identifier)
        view.addSubview(collectionView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        collectionView.addGestureRecognizer(tap)
        navigator.pager = self
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasPlacedStart, collectionView.bounds.width > 0 else { return }
        hasPlacedStart = true
        if let index = navigator.index, index > 0 {
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: false)
        }
    }

    // MARK: - ImagePaging

    func display(page: Int, animated: Bool) {
        guard page >= 0, page < navigator.pageCount, page != reportedIndex else { return }
        reportedIndex = page
        collectionView.scrollToItem(at: IndexPath(item: page, section: 0), at: .top, animated: animated && !UIAccessibility.isReduceMotionEnabled)
    }

    // MARK: - Data source

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        navigator.pageCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageStripCell.identifier, for: indexPath) as! ImageStripCell
        let index = indexPath.item
        cell.show(index: index) { [weak self] in
            await self?.loadImage(at: index)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            Task { _ = await loadImage(at: indexPath.item) }
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
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
            let top = collectionView.indexPathsForVisibleItems.map(\.item).min() ?? 0
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
        // The page at the upper third of the screen is the one being read.
        let probe = CGPoint(x: scrollView.bounds.midX, y: scrollView.contentOffset.y + scrollView.bounds.height / 3)
        guard let index = collectionView.indexPathForItem(at: probe)?.item, index != reportedIndex else { return }
        reportedIndex = index
        navigator.didShow(index)
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
        let distance = collectionView.bounds.height * 0.85 * (forward ? 1 : -1)
        let maxOffset = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
        let target = min(max(collectionView.contentOffset.y + distance, 0), maxOffset)
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.collectionView.contentOffset.y = target
        }
    }
}

private final class ImageStripCell: UICollectionViewCell {
    static let identifier = "ImageStripCell"
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var loading: Task<Void, Never>?
    private var index: Int?

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
    }

    func show(index: Int, load: @escaping @MainActor () async -> UIImage?) {
        self.index = index
        accessibilityLabel = String(localized: "Page \(index + 1)", bundle: .module)
        spinner.startAnimating()
        loading = Task { [weak self] in
            let image = await load()
            guard let self, !Task.isCancelled, self.index == index else { return }
            spinner.stopAnimating()
            imageView.image = image
        }
    }
}
#endif
