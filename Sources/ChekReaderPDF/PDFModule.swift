public import ChekReaderCore
#if canImport(PDFKit)
import Foundation
import PDFKit
#endif

/// PDF through PDFKit.
///
/// Register it once at launch: `ReaderFormats.register(PDFModule.self)`.
///
/// A PDF opens as one resource, ``href``, with a position per page.
/// Locators point at a page with a `page=N` fragment, 1-based, as Readium's
/// do. Files are memory-mapped, so a large PDF isn't read into memory to
/// open it. Local files, in-memory data, HTTP URLs and resource providers
/// open; a provider returns the whole file for
/// ``PublicationSource/wholePublicationHref``.
///
/// PDFKit is only on Apple platforms. Elsewhere, opening a PDF fails with
/// ``ReaderError/notYetImplemented(_:)``.
public enum PDFModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.pdf]

    /// The href of a PDF publication's one resource.
    public static let href = "publication.pdf"

    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        #if canImport(PDFKit)
        let data = try await source.wholeFile(limits: limits)
        try ReaderError.checkCancellation()
        return try PDFParser.parse(data)
        #else
        throw .notYetImplemented(format)
        #endif
    }
}
