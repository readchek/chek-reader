import ChekReaderCore
import Foundation

/// Turns a KF8 book's text and tables into XHTML files, stylesheets and a
/// table of contents.
///
/// The text holds flows: flow 0 is every XHTML file cut into skeletons and
/// fragments, and the others are stylesheets and SVG images. Files are
/// rebuilt from the skeleton and fragment tables, then `kindle:` URLs are
/// rewritten into relative hrefs. Links name a fragment and an offset into
/// it, so their targets are found in the rebuilt files before anything is
/// changed, and get an `id` if they have none.
struct KF8Content {
    /// A generated resource: a file, stylesheet or SVG image.
    struct Resource: Sendable {
        let href: String
        let mediaType: String
        let data: Data
    }

    /// A table of contents entry from the NCX index: a fragment and offset.
    struct NCXEntry: Sendable {
        let fragment: Int
        let offset: Int
        let title: String
        let depth: Int
    }

    private(set) var parts: [Resource] = []
    private(set) var flowResources: [Resource] = []
    private(set) var tableOfContents: [Link] = []
    private(set) var warnings: [PublicationWarning] = []

    private var builtParts: [KF8Tables.Part] = []
    private let fragments: [KF8Tables.Fragment]
    /// The ids given to link targets, by file and tag start.
    private var anchorIDs: [Int: [Int: String]] = [:]
    /// Ids to add to tags that had none, by file and tag start.
    private var insertedIDs: [Int: [Int: String]] = [:]

    static let mediaType = XHTML.mediaType

    init(
        text: [UInt8],
        fdst: [UInt8]?,
        skeletons: [KF8Tables.Skeleton],
        fragments: [KF8Tables.Fragment],
        ncx: [NCXEntry],
        resources: MOBIResources,
        limit: Int
    ) throws(ReaderError) {
        self.fragments = fragments
        var messages: [String] = []
        let flows = KF8Tables.flows(text: text, fdst: fdst, warnings: &messages)
        builtParts = try KF8Tables.parts(text: flows[0], skeletons: skeletons, fragments: fragments, limit: limit, warnings: &messages)
        warnings += messages.map { PublicationWarning($0) }
        guard !builtParts.isEmpty else {
            throw .malformed(reason: "The KF8 skeleton table lists no files.")
        }
        try ReaderError.checkCancellation()

        // Flows after the first are served as files of their own.
        var flowPaths: [Int: String] = [:]
        var flowTypes: [Int: String] = [:]
        for (number, flow) in flows.enumerated().dropFirst() {
            let isSVG = Self.isSVG(flow)
            flowPaths[number] = (isSVG ? "images/flow" : "styles/flow") + MOBIResources.name(number) + (isSVG ? ".svg" : ".css")
            flowTypes[number] = isSVG ? "image/svg+xml" : "text/css"
        }

        // Find every link target before any file changes, since targets
        // are offsets into the files as rebuilt.
        var links: [KindleURL] = []
        for part in builtParts {
            _ = KindleURL.rewrite(part.bytes, resolve: { url in
                links.append(url)
                return nil
            }, unresolved: { _ in })
        }
        var positionHrefs: [KindleURL: String] = [:]
        for url in links {
            if case .position(let fragment, let offset) = url, positionHrefs[url] == nil {
                positionHrefs[url] = href(fragment: fragment, offset: offset)
            }
        }
        var entries: [TableOfContentsBuilder.Entry] = []
        for entry in ncx {
            if let target = href(fragment: entry.fragment, offset: entry.offset) {
                entries.append(TableOfContentsBuilder.Entry(title: entry.title, href: "text/" + target, depth: entry.depth))
            } else {
                warnings.append(PublicationWarning("The table of contents entry \"\(entry.title)\" points outside the text; it was left out."))
            }
        }
        tableOfContents = TableOfContentsBuilder.links(entries, mediaType: Self.mediaType)
        if tableOfContents.isEmpty {
            warnings.append(PublicationWarning("The book has no table of contents."))
        }
        try ReaderError.checkCancellation()

        var unresolved: Set<String> = []
        func resolve(_ url: KindleURL) -> String? {
            switch url {
            case .embed(let number):
                return resources.path(number).map { "../" + $0 }
            case .flow(let number):
                return flowPaths[number].map { "../" + $0 }
            case .position:
                return positionHrefs[url]
            }
        }

        for (number, part) in builtParts.enumerated() {
            var bytes = part.bytes
            // From the end, so earlier offsets stay valid.
            for (start, id) in (insertedIDs[number] ?? [:]).sorted(by: { $0.key > $1.key }) {
                guard let tag = Markup.tag(at: start, in: bytes) else { continue }
                let nameEnd = start + 1 + tag.name.utf8.count
                bytes.insert(contentsOf: Array(" id=\"\(id)\"".utf8), at: nameEnd)
            }
            bytes = KindleURL.rewrite(bytes, resolve: resolve, unresolved: { _ = unresolved.insert($0) })
            parts.append(Resource(href: "text/" + Self.fileName(number), mediaType: Self.mediaType, data: Data(bytes)))
        }
        for (number, flow) in flows.enumerated().dropFirst() {
            guard let path = flowPaths[number], let type = flowTypes[number] else { continue }
            // Stylesheets sit one folder down, as files do, so the same
            // relative paths work for fonts and images.
            let bytes = KindleURL.rewrite(flow, resolve: resolve, unresolved: { _ = unresolved.insert($0) })
            flowResources.append(Resource(href: path, mediaType: type, data: Data(bytes)))
        }
        for url in unresolved.sorted() {
            warnings.append(PublicationWarning("The book refers to \(url), which it doesn't have; the reference was left as it is."))
        }
    }

    /// `part0000.xhtml` for file 0.
    static func fileName(_ number: Int) -> String {
        "part\(MOBIResources.name(number)).xhtml"
    }

    /// Whether a flow is an SVG image rather than a stylesheet.
    static func isSVG(_ flow: [UInt8]) -> Bool {
        let start = flow.firstIndex { !Markup.isSpace($0) } ?? flow.count
        let prefix = Array(flow[start..<min(flow.count, start + 5)])
        return prefix.hasSignature("<svg") || prefix.hasSignature("<?xml")
    }

    /// The href, relative to the text folder, of the place `offset` bytes
    /// into fragment `fragment`, giving the tag there an id if it needs one.
    private mutating func href(fragment: Int, offset: Int) -> String? {
        guard fragment >= 0, fragment < fragments.count, offset >= 0 else { return nil }
        let position = fragments[fragment].insertPosition + offset
        guard let number = builtParts.firstIndex(where: { $0.start <= position && position < $0.end }) else {
            return nil
        }
        let fileName = Self.fileName(number)
        let bytes = builtParts[number].bytes
        guard let tag = Self.targetTag(in: bytes, at: position - builtParts[number].start),
              !["html", "head", "body"].contains(tag.name)
        else {
            return fileName
        }
        let start = tag.range.lowerBound
        if let id = anchorIDs[number]?[start] {
            return fileName + "#" + id
        }
        let id: String
        if let existing = Markup.attributes(of: tag, in: bytes).first(where: { $0.name == "id" })?.value, !existing.isEmpty {
            id = existing
        } else {
            id = "kf8pos-\(start)"
            insertedIDs[number, default: [:]][start] = id
        }
        anchorIDs[number, default: [:]][start] = id
        return fileName + "#" + id
    }

    /// The start tag a link to `offset` should go to: the tag `offset` is
    /// in, or the first start tag after it.
    static func targetTag(in bytes: [UInt8], at offset: Int) -> Markup.Tag? {
        guard offset >= 0, offset < bytes.count else { return nil }
        if let open = bytes[...offset].lastIndex(of: Markup.lessThan),
           let tag = Markup.tag(at: open, in: bytes), tag.range.contains(offset), tag.kind == .start {
            return tag
        }
        var position = offset
        while let start = Markup.firstIndex(of: Markup.lessThan, in: bytes, from: position) {
            if let tag = Markup.tag(at: start, in: bytes) {
                if tag.kind == .start {
                    return tag
                }
                position = tag.range.upperBound
            } else {
                position = start + 1
            }
        }
        return nil
    }
}
