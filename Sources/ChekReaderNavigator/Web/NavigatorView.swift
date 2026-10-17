#if canImport(WebKit) && canImport(SwiftUI)
public import SwiftUI
import WebKit

/// Shows the controller's publication with no controls, for apps that
/// draw their own interface around it.
///
/// ```swift
/// NavigatorView(controller: controller)
///     .overlay(alignment: .bottom) { MyProgressBar(controller: controller) }
/// ```
public struct NavigatorView: View {
    private let controller: ReaderController

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public var body: some View {
        if controller.state == .ready, controller.publication != nil {
            WebNavigatorView(controller: controller)
                .id(controller.session)
        }
    }
}

/// Owns one session's ``WebNavigator``, created when the view appears so
/// re-evaluating the parent never builds a second web page.
private struct WebNavigatorView: View {
    let controller: ReaderController
    @State private var navigator: WebNavigator?

    init(controller: ReaderController) {
        self.controller = controller
        self.navigator = nil
    }

    var body: some View {
        ZStack {
            if let navigator {
                WebView(navigator.page)
            }
        }
        .task {
            guard navigator == nil, let publication = controller.publication else { return }
            let created = WebNavigator(controller: controller, publication: publication)
            navigator = created
            await created.start()
        }
    }
}
#endif
