#if canImport(SwiftUI) && canImport(WebKit)
public import ChekReaderCore
public import ChekReaderNavigator
import Foundation
public import SwiftUI

/// Searches the open publication's text. Choosing a result moves the
/// reader to it and dismisses the view.
public struct SearchView: View {
    private let controller: ReaderController
    @State private var query = ""
    @State private var phase: Phase = .idle
    @State private var search: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case idle
        case searching
        case found([Locator], for: String)
        case failed(ReaderError)
    }

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    ContentUnavailableView {
                        Label { Text("Search", bundle: #bundle) } icon: { Image(systemName: "magnifyingglass") }
                    } description: {
                        Text("Find a word or phrase in this publication.", bundle: #bundle)
                    }
                case .searching:
                    ProgressView()
                case .found(let results, let query) where results.isEmpty:
                    ContentUnavailableView.search(text: query)
                case .found(let results, _):
                    List {
                        Section {
                            ForEach(results.indices, id: \.self) { index in
                                row(results[index])
                            }
                        } header: {
                            Text("\(results.count) results", bundle: #bundle)
                        }
                    }
                    .listStyle(.plain)
                case .failed(let error):
                    ContentUnavailableView {
                        Label { Text("Search Failed", bundle: #bundle) } icon: { Image(systemName: "exclamationmark.triangle") }
                    } description: {
                        Text(verbatim: error.localizedDescription)
                    }
                }
            }
            .navigationTitle(Text("Search", bundle: #bundle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
            }
        }
        .searchable(text: $query, prompt: Text("Find in publication", bundle: #bundle))
        .onSubmit(of: .search) { start(after: .zero) }
        .onChange(of: query) { start(after: .milliseconds(300)) }
        .onDisappear { search?.cancel() }
    }

    private func row(_ result: Locator) -> some View {
        Button {
            Task {
                await controller.go(to: result)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let title = result.title {
                    Text(verbatim: title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                snippet(result.text)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
    }

    private func snippet(_ text: Locator.Text?) -> Text {
        Text(verbatim: text?.before ?? "")
            + Text(verbatim: text?.highlight ?? "").bold()
            + Text(verbatim: text?.after ?? "")
    }

    /// Searches once typing pauses, so each keystroke doesn't read the book.
    private func start(after delay: Duration) {
        search?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            phase = .idle
            return
        }
        if case .found(_, let previous) = phase, previous == query { return }
        search = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            phase = .searching
            do throws(ReaderError) {
                let results = try await controller.search(for: query)
                guard !Task.isCancelled else { return }
                phase = .found(results, for: query)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error)
            }
        }
    }
}
#endif
