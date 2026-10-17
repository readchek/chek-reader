import ChekReaderCore
import Foundation

/// Converts a FictionBook document into a ``Publication`` of generated
/// XHTML documents and decoded images.
struct FB2Parser {
    /// The folder generated documents go in, from the publication's root.
    static let textFolder = "text"

    let limits: ReaderLimits
    let format: ReaderFormat
    private var warnings: [PublicationWarning] = []

    init(limits: ReaderLimits, format: ReaderFormat) {
        self.limits = limits
        self.format = format
    }

    /// One generated XHTML document.
    private struct Document {
        /// The file name in ``FB2Parser/textFolder``.
        var file: String
        var title: String?
        /// The body elements it's made from.
        var nodes: [MarkupNode]
        /// The heading level its top-level titles start from.
        var depth: Int
        var tableOfContents: [Link]

        var href: String { "\(FB2Parser.textFolder)/\(file)" }
    }

    /// Parses `data`, the bytes of a `.fb2` file.
    ///
    /// The bytes go to the XML parser as they are, so books that declare
    /// another encoding, as many in `windows-1251` do, are decoded by it.
    mutating func parse(_ data: Data) throws(ReaderError) -> Publication {
        let root = try XMLTree.parse(data, limits: limits)
        guard root.name == "FictionBook" else {
            throw .malformed(reason: "The root element is <\(root.name)>, not <FictionBook>. Check that the file is a FictionBook 2 document.")
        }
        var bodies = root.elements(named: "body")
        guard !bodies.isEmpty else {
            throw .malformed(reason: "The FictionBook has no <body>, so it has no text to show.")
        }
        let (metadata, coverID) = FB2Metadata.read(root)
        try ReaderError.checkCancellation()

        let binaries = try FB2Binaries.decode(root, limits: limits, warnings: &warnings)
        try ReaderError.checkCancellation()

        // Nested sections need ids for the table of contents to point at.
        var existingIDs: [String] = []
        for body in bodies {
            Self.collectIDs(in: body, into: &existingIDs)
        }
        var usedIDs = Set(existingIDs)
        var generated = 0
        for index in bodies.indices {
            Self.assignSectionIDs(&bodies[index], used: &usedIDs, counter: &generated)
        }

        let documents = plan(bodies, bookTitle: metadata.title)
        try ReaderError.checkCancellation()

        // Links can point forward, so every id's document is found before
        // anything is rendered.
        var documentForID: [String: String] = [:]
        for document in documents {
            var ids: [String] = []
            for node in document.nodes {
                Self.collectIDs(in: node, into: &ids)
            }
            for id in ids where documentForID[id] == nil {
                documentForID[id] = document.file
            }
        }
        let imageForID = Dictionary(binaries.map { ($0.id, $0.href) }, uniquingKeysWith: { first, _ in first })

        var files: [String: Data] = [FB2Stylesheet.href: FB2Stylesheet.data]
        var renderer = FB2Renderer(documentForID: documentForID, imageForID: imageForID)
        for document in documents {
            try ReaderError.checkCancellation()
            renderer.currentDocument = document.file
            let body = renderer.render(document.nodes, depth: document.depth)
            files[document.href] = XHTML.document(
                title: document.title,
                language: metadata.languages.first,
                body: body,
                stylesheets: ["../" + FB2Stylesheet.href]
            )
        }
        warnings += renderer.warnings

        var resources = [Link(href: FB2Stylesheet.href, mediaType: "text/css")]
        for binary in binaries {
            files[binary.href] = binary.data
            resources.append(Link(href: binary.href, mediaType: binary.mediaType, rels: binary.id == coverID ? ["cover"] : []))
        }
        if let coverID, imageForID[coverID] == nil {
            warnings.append(PublicationWarning("The cover page shows \"#\(coverID)\", which isn't a binary in the book. The publication has no cover."))
        }

        return Publication(
            format: format,
            metadata: metadata,
            readingOrder: documents.map { Link(href: $0.href, mediaType: XHTML.mediaType, title: $0.title) },
            tableOfContents: documents.flatMap(\.tableOfContents),
            resources: resources,
            warnings: warnings,
            container: MemoryContainer(files)
        )
    }

    /// Splits the bodies into documents: one for each top-level section of
    /// the main body, then one for each other body, such as the notes.
    ///
    /// Anything in the main body before its first section, such as the
    /// book's title and epigraph, goes in the first document, and anything
    /// between sections goes with the section before it.
    private mutating func plan(_ bodies: [MarkupNode], bookTitle: String?) -> [Document] {
        var groups: [[MarkupNode]] = []
        for element in bodies[0].elements {
            if element.name == "section", let last = groups.last, last.contains(where: { $0.name == "section" }) {
                groups.append([element])
            } else if groups.isEmpty {
                groups.append([element])
            } else {
                groups[groups.count - 1].append(element)
            }
        }
        if groups.isEmpty {
            warnings.append(PublicationWarning("The main body has no text. It opens as an empty document."))
            groups = [[]]
        }

        var documents: [Document] = []
        var files: Set<String> = []
        for (index, group) in groups.enumerated() {
            let number = String(index + 1)
            let file = "section-" + String(repeating: "0", count: max(0, 4 - number.count)) + number + ".xhtml"
            files.insert(file)
            let sections = group.filter { $0.name == "section" }
            var tableOfContents = sections.flatMap { tocEntries(for: $0, file: file, anchored: false) }
            if sections.isEmpty, let title = group.first(where: { $0.name == "title" }).flatMap(Self.titleText) {
                tableOfContents = [Link(href: "\(Self.textFolder)/\(file)", title: title)]
            }
            documents.append(Document(
                file: file,
                title: tableOfContents.first?.title ?? bookTitle,
                nodes: group,
                depth: 0,
                tableOfContents: tableOfContents
            ))
        }

        for body in bodies.dropFirst() {
            let base = body.attribute("name").flatMap(FB2Path.component) ?? "body"
            let file = FB2Path.unique(base, extension: "xhtml", in: &files)
            let title = body.firstElement(named: "title").flatMap(Self.titleText) ?? "Notes"
            documents.append(Document(
                file: file,
                title: title,
                nodes: body.elements,
                // Each note is a section with a short title, such as its
                // number, which shouldn't be the largest heading.
                depth: 1,
                tableOfContents: [Link(href: "\(Self.textFolder)/\(file)", title: title)]
            ))
        }
        return documents
    }

    /// The table of contents entries for `section` and the sections in it.
    /// A section without a title is left out, and its sections take its
    /// place.
    ///
    /// - Parameter anchored: Whether the entry points at the section's id
    ///   rather than the start of its document.
    private func tocEntries(for section: MarkupNode, file: String, anchored: Bool) -> [Link] {
        let children = section.elements(named: "section").flatMap { tocEntries(for: $0, file: file, anchored: true) }
        guard let title = section.firstElement(named: "title").flatMap(Self.titleText) else {
            return children
        }
        var href = "\(Self.textFolder)/\(file)"
        if anchored, let id = section.attribute("id") {
            href += "#\(id)"
        }
        return [Link(href: href, title: title, children: children)]
    }

    /// A `<title>`'s text on one line. Its paragraphs are joined with
    /// spaces, since they often have no whitespace between them.
    private static func titleText(_ title: MarkupNode) -> String? {
        let lines = title.elements(named: "p").compactMap(\.trimmedText)
        return lines.isEmpty ? title.trimmedText : lines.joined(separator: " ")
    }

    /// Appends the ids of `node` and every element in it.
    private static func collectIDs(in node: MarkupNode, into ids: inout [String]) {
        if let id = node.attribute("id"), !id.isEmpty {
            ids.append(id)
        }
        for child in node.elements {
            collectIDs(in: child, into: &ids)
        }
    }

    /// Gives every section without an id one that isn't in `used`.
    private static func assignSectionIDs(_ node: inout MarkupNode, used: inout Set<String>, counter: inout Int) {
        if node.name == "section", (node.attribute("id") ?? "").isEmpty {
            var id: String
            repeat {
                counter += 1
                id = "fb2-section-\(counter)"
            } while used.contains(id)
            used.insert(id)
            node.attributes["id"] = id
        }
        for index in node.children.indices {
            guard case .element(var child) = node.children[index] else { continue }
            assignSectionIDs(&child, used: &used, counter: &counter)
            node.children[index] = .element(child)
        }
    }
}
