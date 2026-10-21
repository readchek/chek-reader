#if canImport(SwiftUI) && canImport(WebKit)
public import ChekReaderCore
public import ChekReaderNavigator
public import SwiftUI

/// The standard controls over a ``NavigatorView``: a title bar with the
/// table of contents, search and appearance settings, and a position
/// slider along the bottom.
///
/// ``ReaderView`` shows them already. An app that lays out its own screen
/// around a `NavigatorView` can overlay them itself:
///
/// ```swift
/// NavigatorView(controller: controller)
///     .overlay { ReaderControls(controller: controller, isVisible: showsControls) }
/// ```
public struct ReaderControls: View {
    private let controller: ReaderController
    private let isVisible: Bool
    @State private var sheet: Sheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Sheet: String, Identifiable {
        case contents, search, appearance
        var id: String { rawValue }
    }

    public init(controller: ReaderController, isVisible: Bool = true) {
        self.controller = controller
        self.isVisible = isVisible
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                titleBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if isVisible {
                ReaderPositionBar(controller: controller)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isVisible)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .contents: TableOfContentsView(controller: controller)
            case .search: SearchView(controller: controller)
            case .appearance: AppearanceView(controller: controller)
            }
        }
    }

    private var titleBar: some View {
        GlassEffectContainer {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = controller.publication?.metadata.title {
                        Text(verbatim: title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    ChapterTitle(controller: controller)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect()
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                buttons
                    .padding(8)
                    .glassEffect()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var buttons: some View {
        HStack(spacing: 4) {
            Button {
                sheet = .contents
            } label: {
                Label { Text("Contents", bundle: #bundle) } icon: { Image(systemName: "list.bullet") }
            }
            .disabled(!hasContents)
            Button {
                sheet = .search
            } label: {
                Label { Text("Search", bundle: #bundle) } icon: { Image(systemName: "magnifyingglass") }
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!hasText)
            Button {
                sheet = .appearance
            } label: {
                Label { Text("Appearance", bundle: #bundle) } icon: { Image(systemName: "textformat.size") }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
    }

    private var hasContents: Bool {
        guard let publication = controller.publication else { return false }
        return !publication.tableOfContents.isEmpty || publication.readingOrder.count > 1
    }

    /// Comics have no text to search.
    private var hasText: Bool {
        guard let publication = controller.publication else { return false }
        return ![.cbz, .cbt, .cbr, .cb7].contains(publication.format)
    }
}

/// The chapter's title, on its own so only it redraws as the location moves.
private struct ChapterTitle: View {
    let controller: ReaderController

    var body: some View {
        if let title = controller.location?.title {
            Text(verbatim: title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// A slider through the publication's positions, with the position number,
/// and buttons for the chapter before and after.
struct ReaderPositionBar: View {
    let controller: ReaderController
    /// The position the slider is being dragged to, shown until it's let go.
    @State private var dragged: Double?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await goToChapter(offset: -1) }
            } label: {
                Label { Text("Previous chapter", bundle: #bundle) } icon: { Image(systemName: "chevron.backward") }
            }
            .disabled(chapterIndex.map { $0 == 0 } ?? true)
            if let positions = controller.positions, positions.count > 1 {
                let count = positions.count
                let shown = Int(dragged ?? Double(position))
                VStack(spacing: 2) {
                    Slider(value: sliderValue, in: 1...Double(count), step: 1) {
                        Text("Reading position", bundle: #bundle)
                    } onEditingChanged: { editing in
                        guard !editing, let dragged else { return }
                        self.dragged = nil
                        Task { await controller.go(toPosition: Int(dragged)) }
                    }
                    .accessibilityValue(Text("\(shown) of \(count)", bundle: #bundle))
                    Text("\(shown) of \(count)", bundle: #bundle)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                // The slider runs the way the pages do.
                .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
            } else {
                Spacer(minLength: 0)
            }
            Button {
                Task { await goToChapter(offset: 1) }
            } label: {
                Label { Text("Next chapter", bundle: #bundle) } icon: { Image(systemName: "chevron.forward") }
            }
            .disabled(chapterIndex.map { $0 + 1 >= (controller.publication?.readingOrder.count ?? 0) } ?? true)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sliderValue: Binding<Double> {
        Binding {
            dragged ?? Double(position)
        } set: { value in
            dragged = value
        }
    }

    private var position: Int {
        controller.location?.locations.position ?? 1
    }

    private var isRightToLeft: Bool {
        controller.preferences.readingProgression == .rightToLeft
            || (controller.preferences.readingProgression == nil && controller.publication?.metadata.readingProgression == .rightToLeft)
    }

    private var chapterIndex: Int? {
        guard let publication = controller.publication, let location = controller.location else { return nil }
        return publication.readingOrderIndex(of: location)
    }

    private func goToChapter(offset: Int) async {
        guard let publication = controller.publication, let index = chapterIndex,
              publication.readingOrder.indices.contains(index + offset)
        else { return }
        await controller.go(to: publication.readingOrder[index + offset])
    }
}
#endif
