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
        if controller.state == .ready, let publication = controller.publication {
            switch NavigatorKind(publication) {
            case .web:
                WebNavigatorView(controller: controller)
                    .id(controller.session)
            case .pdf:
                PDFNavigatorView(controller: controller)
                    .id(controller.session)
            case .images:
                ImageNavigatorView(controller: controller)
                    .id(controller.session)
            case nil:
                EmptyView()
            }
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
            Color.clear
            if let navigator {
                #if os(iOS)
                // A different transition needs a new page view controller.
                BookPagerView(navigator: navigator) {
                    WebSlotsView(navigator: navigator)
                }
                .id(navigator.pageTransition)
                #else
                WebSlotsView(navigator: navigator)
                #endif
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

/// Every web page, with only the one on screen visible.
private struct WebSlotsView: View {
    let navigator: WebNavigator

    var body: some View {
        ZStack {
            // Every page stays in the hierarchy so it keeps its size and
            // layout, and keeps its view while it's reused for other
            // resources; only the one on screen is visible.
            ForEach(navigator.slots) { slot in
                let isCurrent = slot.resource == navigator.resourceIndex
                WebView(slot.page)
                    .scrollDisabled(true)
                    .opacity(isCurrent ? 1 : 0)
                    .allowsHitTesting(isCurrent)
                    .accessibilityHidden(!isCurrent)
                    .zIndex(isCurrent ? 1 : 0)
            }
        }
    }
}
#endif
