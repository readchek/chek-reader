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

    /// Finds `query` with PDFKit. Each result names its page with a
    /// `page=N` fragment and carries the matched text with some text around
    /// it from that page.
    public static func search(_ publication: Publication, for query: String, options: SearchOptions) async throws(ReaderError) -> [Locator]? {
        #if canImport(PDFKit)
        guard publication.format == .pdf else { return nil }
        let data = try await publication.data(at: href)
        try ReaderError.checkCancellation()
        guard let document = PDFDocument(data: data), !document.isLocked else { return [] }
        let titles = PDFOutline.titles(in: publication.tableOfContents)
        var found: [Locator] = []
        // Where the last match on each page ended, so context comes from
        // the right occurrence when a page repeats the text.
        var searched: [Int: String.Index] = [:]
        for selection in document.findString(query, withOptions: options.compareOptions).prefix(options.limit) {
            try ReaderError.checkCancellation()
            guard let page = selection.pages.first else { continue }
            let index = document.index(for: page)
            guard index != NSNotFound else { continue }
            var text = Locator.Text(highlight: selection.string ?? query)
            if let highlight = text.highlight, let pageText = page.string,
               let range = pageText.range(of: highlight, options: options.compareOptions, range: (searched[index] ?? pageText.startIndex)..<pageText.endIndex) {
                let context = Publication.searchContextLength
                let before = pageText.index(range.lowerBound, offsetBy: -context, limitedBy: pageText.startIndex) ?? pageText.startIndex
                let after = pageText.index(range.upperBound, offsetBy: context, limitedBy: pageText.endIndex) ?? pageText.endIndex
                text.before = String(pageText[before..<range.lowerBound])
                text.after = String(pageText[range.upperBound..<after])
                searched[index] = range.upperBound
            }
            found.append(Locator(
                href: href,
                mediaType: "application/pdf",
                title: titles.last { $0.page <= index }?.title,
                locations: Locator.Locations(
                    fragments: ["page=\(index + 1)"],
                    progression: Double(index) / Double(document.pageCount)
                ),
                text: text
            ))
        }
        return found
        #else
        return nil
        #endif
    }
}

#if canImport(PDFKit)
/// The outline's titles by page, so a result can say which chapter it's in.
private enum PDFOutline {
    /// The first titled table of contents entry on each 0-based page, in
    /// page order, so the title for a page is the last entry at or before
    /// it. A chapter that starts on the same page as its first section
    /// names the page.
    static func titles(in links: [Link]) -> [(page: Int, title: String)] {
        var found: [(page: Int, title: String)] = []
        var pages: Set<Int> = []
        func visit(_ links: [Link]) {
            for link in links {
                if let title = link.title, let hash = link.href.firstIndex(of: "#") {
                    for parameter in link.href[link.href.index(after: hash)...].split(separator: "&") where parameter.hasPrefix("page=") {
                        if let page = Int(parameter.dropFirst(5)), page > 0, pages.insert(page - 1).inserted {
                            found.append((page - 1, title))
                        }
                    }
                }
                visit(link.children)
            }
        }
        visit(links)
        return found.sorted { $0.page < $1.page }
    }
}
#endif
