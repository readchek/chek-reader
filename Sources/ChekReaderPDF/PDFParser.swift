#if canImport(PDFKit)
import ChekReaderCore
import Foundation
import PDFKit

/// Reads a PDF's metadata and outline with PDFKit.
enum PDFParser {
    static func parse(_ data: Data) throws(ReaderError) -> Publication {
        guard let document = PDFDocument(data: data) else {
            throw .malformed(reason: "PDFKit couldn't read the PDF. Check that the file is a complete PDF.")
        }
        // An encrypted PDF that opens without a password, as most do when
        // only printing or copying is restricted, isn't locked.
        guard !document.isLocked else {
            throw .drmProtected(scheme: "a PDF password")
        }
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw .malformed(reason: "The PDF has no pages.")
        }

        let attributes = document.documentAttributes ?? [:]
        func string(_ key: PDFDocumentAttribute) -> String? {
            (attributes[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        func date(_ key: PDFDocumentAttribute) -> String? {
            (attributes[key] as? Date).map { $0.formatted(.iso8601) }
        }
        let authors = (string(.authorAttribute)?.split(separator: ";") ?? [])
            .compactMap { String($0).trimmingCharacters(in: .whitespaces).nilIfEmpty }
            .map { Publication.Contributor(name: $0) }
        var subjects = (attributes[PDFDocumentAttribute.keywordsAttribute] as? [String]) ?? []
        if let subject = string(.subjectAttribute) {
            subjects.insert(subject, at: 0)
        }

        let metadata = Publication.Metadata(
            title: string(.titleAttribute),
            authors: authors,
            published: date(.creationDateAttribute),
            modified: date(.modificationDateAttribute),
            subjects: subjects,
            layout: .fixed
        )

        let href = PDFModule.href
        let reading = Link(href: href, mediaType: "application/pdf")
        var tableOfContents: [Link] = []
        if let root = document.outlineRoot {
            tableOfContents = links(under: root, in: document, depth: 0)
        }

        return Publication(
            format: .pdf,
            metadata: metadata,
            readingOrder: [reading],
            tableOfContents: tableOfContents,
            container: MemoryContainer([href: data], positionCounts: [href: pageCount])
        )
    }

    /// Outlines can nest without bound in a hostile file; deeper entries
    /// than this are dropped.
    private static let maxOutlineDepth = 32

    private static func links(under outline: PDFOutline, in document: PDFDocument, depth: Int) -> [Link] {
        guard depth < maxOutlineDepth else { return [] }
        var links: [Link] = []
        for index in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: index) else { continue }
            let children = links(under: child, in: document, depth: depth + 1)
            let page = (child.destination?.page ?? (child.action as? PDFActionGoTo)?.destination.page)
                .map { document.index(for: $0) }
                .flatMap { $0 == NSNotFound ? nil : $0 }
            // An entry without a destination of its own goes where its first child does.
            let href = page.map { "\(PDFModule.href)#page=\($0 + 1)" } ?? children.first?.href
            guard let href else { continue }
            links.append(Link(href: href, mediaType: "application/pdf", title: child.label?.nilIfEmpty, children: children))
        }
        return links
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
