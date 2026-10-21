#if canImport(SwiftUI) && canImport(WebKit)
public import ChekReaderCore
public import ChekReaderNavigator
public import SwiftUI

/// A complete reader: content plus the standard controls.
///
/// A tap in the middle of the page shows and hides the controls: the
/// title bar with the table of contents, search and appearance settings,
/// and the position slider. With VoiceOver on, the controls stay visible.
///
/// ```swift
/// ReaderView(source: .file(url), initialLocation: savedLocation) { location in
///     save(location)
/// }
/// ```
public struct ReaderView: View {
    private let source: PublicationSource
    private let sourceID: String
    private let initialLocation: Locator?
    private let onLocationChange: (@MainActor (Locator) -> Void)?
    private let onPreferencesChange: (@MainActor (ReaderPreferences) -> Void)?
    @State private var controller: ReaderController
    @State private var showsControls = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// - Parameters:
    ///   - source: Where the publication comes from.
    ///   - initialLocation: Where to open it, such as the location saved
    ///     last time, or `nil` for the start.
    ///   - preferences: The reading settings to start with. The appearance
    ///     sheet changes them, and `onPreferencesChange` reports each change
    ///     so the app can keep them.
    ///   - onLocationChange: Called as the reader moves, with a location
    ///     the app can store and pass back as `initialLocation`.
    ///   - onPreferencesChange: Called when the reader changes a setting.
    public init(
        source: PublicationSource,
        initialLocation: Locator? = nil,
        preferences: ReaderPreferences = ReaderPreferences(),
        onLocationChange: (@MainActor (Locator) -> Void)? = nil,
        onPreferencesChange: (@MainActor (ReaderPreferences) -> Void)? = nil
    ) {
        self.source = source
        self.sourceID = Self.identity(of: source)
        self.initialLocation = initialLocation
        self.onLocationChange = onLocationChange
        self.onPreferencesChange = onPreferencesChange
        _controller = State(wrappedValue: ReaderController(preferences: preferences))
    }

    public var body: some View {
        ZStack {
            NavigatorView(controller: controller)
                .ignoresSafeArea()
            ReaderStateView(state: controller.state)
            ReaderControls(controller: controller, isVisible: showsControls || voiceOver)
            ChangeReporter(controller: controller, onLocationChange: onLocationChange, onPreferencesChange: onPreferencesChange)
        }
        // VoiceOver's page-scrolling swipes turn the reader's pages.
        .accessibilityScrollAction { edge in
            Task {
                switch edge {
                case .leading, .top: _ = await controller.goBackward()
                case .trailing, .bottom: _ = await controller.goForward()
                }
            }
        }
        .onChange(of: controller.middleTapCount) {
            showsControls.toggle()
        }
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
            EmptyView()
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
            EmptyView()
        }
    }
}

/// Watches the fast-changing values on its own, so the reader view isn't
/// redrawn for every page turn.
private struct ChangeReporter: View {
    let controller: ReaderController
    let onLocationChange: (@MainActor (Locator) -> Void)?
    let onPreferencesChange: (@MainActor (ReaderPreferences) -> Void)?

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: controller.location) { _, location in
                if let location, controller.state == .ready {
                    onLocationChange?(location)
                }
            }
            .onChange(of: controller.preferences) { _, preferences in
                onPreferencesChange?(preferences)
            }
    }
}
#endif
