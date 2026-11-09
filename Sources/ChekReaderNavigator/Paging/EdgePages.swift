#if canImport(SwiftUI)
public import SwiftUI

/// The pages an app gives a publication's ends, read by the page-turning
/// views from the environment.
struct ReaderEdgePages: Sendable {
    /// What's before the first page.
    var start: ReaderEdgePage
    /// What's after the last page.
    var end: ReaderEdgePage
    /// What each end's page shows.
    var content: @MainActor @Sendable (ReaderEdge) -> AnyView

    func page(at edge: ReaderEdge) -> ReaderEdgePage {
        switch edge {
        case .start: start
        case .end: end
        }
    }

    /// Whether `edge` has a page of its own.
    func has(_ edge: ReaderEdge) -> Bool {
        page(at: edge) != .none
    }

    /// Whether reading goes on past `edge`'s page.
    func goesThrough(_ edge: ReaderEdge) -> Bool {
        page(at: edge) == .through
    }
}

extension EnvironmentValues {
    @Entry var readerEdgePages: ReaderEdgePages?
}

extension View {
    /// Gives the publication's ends pages of their own, turned onto as the
    /// pages are: with the same swipe following your finger, slide or curl,
    /// and the same taps and keys.
    ///
    /// One turn on past the last page shows `content(.end)`. When reading
    /// goes ``ReaderEdgePage/through`` it, one more turns onto a plain page
    /// past it and counts in ``ReaderController/turnsPastEnd``, so the app
    /// can open what comes next there; a ``ReaderEdgePage/stop`` is as far
    /// as reading goes. The start works the same way, counting in
    /// ``ReaderController/turnsPastStart``. While an end's page or the one
    /// past it shows, ``ReaderController/edge`` says which end it is.
    ///
    /// The content is hosted on its own, outside this view's environment,
    /// so pass it anything it reads from there. It takes taps itself; turn
    /// from it with ``ReaderController/goForward()`` and
    /// ``ReaderController/goBackward()``.
    ///
    /// Comics turned a page at a time and books use these pages. Comics
    /// that scroll and PDFs leave the ends to the app, as before.
    ///
    /// - Parameters:
    ///   - start: What's before the first page, such as a page naming the
    ///     chapter before, which reading goes through.
    ///   - end: What's after the last page.
    ///   - content: The page for an end.
    public func readerEdgePages<Content: View>(
        start: ReaderEdgePage,
        end: ReaderEdgePage,
        @ViewBuilder content: @escaping @MainActor @Sendable (ReaderEdge) -> Content
    ) -> some View {
        environment(\.readerEdgePages, ReaderEdgePages(start: start, end: end) { AnyView(content($0)) })
    }
}
#endif

#if os(iOS) && canImport(SwiftUI)
import UIKit

/// An end's own page, showing what the app gave it.
final class EdgePageController: UIViewController {
    let edge: ReaderEdge
    private let hosting: UIHostingController<AnyView>
    private let pageColor: UIColor

    init(edge: ReaderEdge, content: AnyView, pageColor: UIColor) {
        self.edge = edge
        self.pageColor = pageColor
        hosting = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Opaque, so a curl has a page to lift and a slide doesn't show
        // the page underneath.
        view.backgroundColor = pageColor
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        isAccessibilityElement = false
    }

    func update(_ content: AnyView) {
        hosting.rootView = content
    }
}

/// The page past an end: the page's own color while what comes next
/// opens, so the turn onto it is a turn like any other.
final class PastEdgePageController: UIViewController {
    let edge: ReaderEdge
    private let pageColor: UIColor
    private let spinner = UIActivityIndicatorView(style: .large)

    init(edge: ReaderEdge, pageColor: UIColor) {
        self.edge = edge
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
        spinner.color = pageColor.isDark ? .lightGray : .darkGray
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        spinner.startAnimating()
    }
}

extension UIColor {
    /// Whether text on it should be light.
    var isDark: Bool {
        var white: CGFloat = 0
        guard getWhite(&white, alpha: nil) else { return true }
        return white < 0.5
    }
}
#endif
