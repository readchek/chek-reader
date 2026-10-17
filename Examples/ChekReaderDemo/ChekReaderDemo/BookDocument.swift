import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let cbz = UTType(importedAs: "com.readchek.cbz")
}

/// A read-only document: the demo opens books and never writes them.
@Observable
final class BookDocument: ReadableDocument {
    static let readableContentTypes: [UTType] = [.epub, .pdf, .cbz, .plainText]

    struct Contents: Sendable {
        var data: Data
        var fileName: String
    }

    var contents: Contents?

    init() {}

    struct Reader: DocumentReader {
        @concurrent
        func read(
            from source: URL, progress: consuming Subprogress
        ) async throws -> sending Contents {
            Contents(
                data: try Data(contentsOf: source, options: .mappedIfSafe),
                fileName: source.lastPathComponent
            )
        }
    }

    func reader(
        configuration: sending ReadConfiguration
    ) -> sending Reader {
        Reader()
    }

    @MainActor
    func apply(
        snapshot: sending Contents,
        previous: sending Contents?
    ) async throws {
        contents = snapshot
    }
}
