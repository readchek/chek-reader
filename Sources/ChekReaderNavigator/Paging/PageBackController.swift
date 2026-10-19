#if os(iOS)
import UIKit

/// The back of a page as it curls: the page's own color, with what's printed
/// on the front showing faintly through in mirror image, as on paper.
///
/// Without a back, a curling page is drawn light gray, which looks wrong on
/// a dark page.
final class PageBackController: UIViewController {
    /// Identifies the front this is the back of.
    let front: AnyHashable
    private let imageView = UIImageView()
    private var image: UIImage?
    private let pageColor: UIColor

    init(front: AnyHashable, image: UIImage?, pageColor: UIColor) {
        self.front = front
        self.image = image
        self.pageColor = pageColor
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pageColor
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        imageView.alpha = 0.12
        imageView.transform = CGAffineTransform(scaleX: -1, y: 1)
        imageView.image = image
        view.addSubview(imageView)
    }

    func setImage(_ image: UIImage?) {
        self.image = image
        if isViewLoaded {
            imageView.image = image
        }
    }
}
#endif
