public import ChekReaderCore
import Foundation

/// FictionBook 2, plain and zipped.
///
/// Register it once at launch: `ReaderFormats.register(FB2Module.self)`.
///
/// A FictionBook is converted to XHTML while it opens: one document for
/// each top-level section of the main body, then one for each other body,
/// such as the notes. Images embedded as `<binary>` elements become
/// resources under `images/`, and links between sections and to notes are
/// rewritten to point at the generated documents.
///
/// Local files, in-memory data, HTTP URLs and resource providers open. A
/// provider returns the whole file for
/// ``PublicationSource/wholePublicationHref``. A zipped FictionBook is read
/// from the first `.fb2` entry in its archive.
public enum FB2Module: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.fb2, .fb2Zip]

    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        let data: Data
        if format == .fb2Zip {
            data = try await bookInArchive(source, limits: limits)
        } else {
            data = try await source.wholeFile(limits: limits)
        }
        try ReaderError.checkCancellation()
        var parser = FB2Parser(limits: limits, format: format)
        return try parser.parse(data)
    }

    /// The bytes of the FictionBook inside a zipped one.
    private static func bookInArchive(_ source: PublicationSource, limits: ReaderLimits) async throws(ReaderError) -> Data {
        let archive: any PublicationContainer
        switch source {
        case .file(let url):
            archive = try ZIPArchive(contentsOf: url, limits: limits)
        case .data(let data, _):
            archive = try ZIPArchive(data: data, limits: limits)
        case .remote(let url, let options):
            archive = try await RemoteZIPArchive.open(url, options: options, limits: limits)
        case .provider:
            // A provider can't list an archive's entries, so it supplies
            // the archive itself.
            let data = try await source.wholeFile(limits: limits)
            archive = try ZIPArchive(data: data, limits: limits)
        case .pages:
            throw .unsupportedFormat(fileName: nil)
        }
        let books = (archive.paths ?? []).filter { path in
            // macOS adds resource forks such as `__MACOSX/._book.fb2`,
            // which end in .fb2 but aren't books.
            let name = path.split(separator: "/").last.map(String.init) ?? path
            return name.lowercased().hasSuffix(".fb2") && !name.hasPrefix("._") && !path.hasPrefix("__MACOSX/")
        }
        guard let path = books.sorted().first else {
            throw .malformed(reason: "The zipped FictionBook has no .fb2 file inside. Check that the archive contains the book.")
        }
        return try await archive.data(at: path)
    }
}
