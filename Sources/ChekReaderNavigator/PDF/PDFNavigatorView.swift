#if canImport(PDFKit) && canImport(SwiftUI)
import PDFKit
import SwiftUI

/// Owns one session's ``PDFNavigator``, created when the view appears so
/// re-evaluating the parent never builds a second PDF view.
struct PDFNavigatorView: View {
    let controller: ReaderController
    @State private var navigator: PDFNavigator?

    init(controller: ReaderController) {
        self.controller = controller
        self.navigator = nil
    }

    var body: some View {
        ZStack {
            if let navigator {
                PDFKitView(view: navigator.view)
            }
        }
        .task {
            guard navigator == nil, let publication = controller.publication else { return }
            let created = PDFNavigator(controller: controller, publication: publication)
            navigator = created
            await created.start()
        }
    }
}

#if os(macOS)
private struct PDFKitView: NSViewRepresentable {
    let view: PDFView

    func makeNSView(context: Context) -> PDFView { view }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#else
private struct PDFKitView: UIViewRepresentable {
    let view: PDFView

    func makeUIView(context: Context) -> PDFView { view }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#endif
#endif
