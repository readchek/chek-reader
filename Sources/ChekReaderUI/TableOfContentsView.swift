#if canImport(SwiftUI) && canImport(WebKit)
public import ChekReaderCore
public import ChekReaderNavigator
import Foundation
public import SwiftUI

/// The publication's table of contents. Choosing an entry moves the
/// reader there and dismisses the view.
///
/// A publication without a table of contents lists its chapters instead.
public struct TableOfContentsView: View {
    private let controller: ReaderController
    private let entries: [Entry]
    /// The resource open when the view appeared, to mark its entry.
    private let currentPath: String?
    @Environment(\.dismiss) private var dismiss

    public init(controller: ReaderController) {
        self.controller = controller
        currentPath = controller.location?.href.split(separator: "#", maxSplits: 1).first.map(String.init)
        if let publication = controller.publication {
            entries = publication.tableOfContents.isEmpty
                ? publication.readingOrder.enumerated().map { Entry(link: $0.element, fallback: $0.offset + 1, path: "\($0.offset)") }
                : publication.tableOfContents.enumerated().map { Entry(link: $0.element, fallback: $0.offset + 1, path: "\($0.offset)") }
        } else {
            entries = []
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label { Text("No Contents", bundle: #bundle) } icon: { Image(systemName: "list.bullet") }
                    } description: {
                        Text("This publication has no table of contents.", bundle: #bundle)
                    }
                } else {
                    List {
                        OutlineGroup(entries, children: \.children) { entry in
                            Button {
                                Task {
                                    await controller.go(to: entry.link)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Text(verbatim: entry.title)
                                        .foregroundStyle(.primary)
                                    if entry.path(of: entry.link.href) == currentPath {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                            .accessibilityLabel(Text("Current chapter", bundle: #bundle))
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(Text("Contents", bundle: #bundle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
            }
        }
    }

    /// A table of contents entry with an identity for the outline, since
    /// two entries can point at the same place.
    struct Entry: Identifiable {
        let id: String
        let link: ChekReaderCore.Link
        let title: String
        /// `nil` rather than empty, so the outline shows no disclosure.
        let children: [Entry]?

        init(link: ChekReaderCore.Link, fallback: Int, path: String) {
            id = path
            self.link = link
            title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? String(localized: "Chapter \(fallback)", bundle: #bundle)
            children = link.children.isEmpty
                ? nil
                : link.children.enumerated().map { Entry(link: $0.element, fallback: $0.offset + 1, path: "\(path).\($0.offset)") }
        }

        func path(of href: String) -> String {
            href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
