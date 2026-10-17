#if canImport(SwiftUI)
public import ChekReaderCore
public import ChekReaderNavigator
public import SwiftUI

/// A complete reader: content plus the standard controls.
///
/// ```swift
/// ReaderView(source: .file(url), initialLocation: savedLocation)
/// ```
public struct ReaderView: View {
    private let source: PublicationSource
    private let sourceID: String
    private let initialLocation: Locator?
    @State private var controller = ReaderController()

    public init(source: PublicationSource, initialLocation: Locator? = nil) {
        self.source = source
        self.sourceID = Self.identity(of: source)
        self.initialLocation = initialLocation
    }

    public var body: some View {
        ReaderStateView(state: controller.state)
            .task(id: sourceID) {
                try? await controller.open(source, at: initialLocation)
            }
    }

    private static func identity(of source: PublicationSource) -> String {
        switch source {
        case .file(let url): url.absoluteString
        case .remote(let url, let options): options.identifier ?? url.absoluteString
        case .data(let data, let fileName): "\(fileName ?? "data")-\(data.count)"
        case .provider(let provider): String(describing: type(of: provider))
        case .pages(let pages): String(describing: type(of: pages))
        }
    }
}

/// Split out so that location changes do not redraw it.
private struct ReaderStateView: View {
    let state: ReaderController.State

    var body: some View {
        switch state {
        case .idle, .opening, .closing:
            ProgressView()
        case .ready:
            Color.clear
        case .failed(let error):
            ContentUnavailableView {
                Image(systemName: "book.closed")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text(verbatim: error.localizedDescription)
            } description: {
                if let suggestion = error.recoverySuggestion {
                    Text(verbatim: suggestion)
                }
            }
        case .closed:
            Color.clear
        }
    }
}
#endif
