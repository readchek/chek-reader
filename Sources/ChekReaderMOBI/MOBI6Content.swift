import ChekReaderCore
import Foundation

/// Turns a MOBI 6 book's single HTML text into chapter documents.
///
/// MOBI 6 text is one HTML stream with `<mbp:pagebreak/>` between
/// chapters. Links are `filepos` attributes holding byte offsets into that
/// stream, and images are `recindex` attributes holding resource numbers.
/// This inserts an anchor at every linked offset, splits the stream at page
/// breaks, and rewrites the links and images into ordinary hrefs. Offsets
/// are found in the original bytes before anything moves, so they stay
/// exact.
struct MOBI6Content {
    struct Part: Sendable {
        let href: String
        let data: Data
    }

    /// A table of contents entry from the NCX index: a `filepos` offset.
    struct NCXEntry: Sendable {
        let position: Int
        let title: String
        let depth: Int
    }

    static let mediaType = "text/html"

    private(set) var parts: [Part] = []
    private(set) var tableOfContents: [Link] = []
    private(set) var warnings: [PublicationWarning] = []

    private let text: [UInt8]
    private let encoding: MOBITextEncoding
    private let tags: [Markup.Tag]

    init(
        text: [UInt8],
        encoding: MOBITextEncoding,
        resources: MOBIResources,
        ncx: [NCXEntry],
        title: String?,
        language: String?
    ) throws(ReaderError) {
        self.text = text
        self.encoding = encoding
        tags = Markup.tags(in: text)

        // Every linked offset: links, guide references and the NCX.
        var targets = Set(ncx.map(\.position))
        var tocGuidePosition: Int?
        for tag in tags where tag.kind == .start {
            let attributes = Markup.attributes(of: tag, in: text)
            guard let position = Self.filepos(in: attributes) else { continue }
            targets.insert(position)
            if tag.name == "reference",
               attributes.contains(where: { $0.name == "type" && $0.value?.lowercased() == "toc" }) {
                tocGuidePosition = tocGuidePosition ?? position
            }
        }
        try ReaderError.checkCancellation()

        // Where each target's anchor goes. An offset inside a tag moves to
        // the tag's start so the anchor never splits markup.
        var anchors: [(position: Int, filepos: Int)] = []
        for target in targets.sorted() {
            guard target >= 0, target <= text.count else {
                warnings.append(PublicationWarning("A link points to offset \(target), past the end of the text; it was removed."))
                continue
            }
            anchors.append((position: tagStart(containing: target) ?? target, filepos: target))
        }
        anchors.sort { $0.position < $1.position }

        let skipped = skippedRanges()
        var rawParts: [[UInt8]] = []
        var current: [UInt8] = []
        var anchorParts: [Int: Int] = [:]
        var cursor = 0
        var nextAnchor = 0

        // Copies text up to `end`, placing anchors at their offsets. Anchors
        // inside a skipped range land just after it.
        func copy(upTo end: Int) {
            while nextAnchor < anchors.count, anchors[nextAnchor].position < end {
                let position = max(anchors[nextAnchor].position, cursor)
                current += text[cursor..<position]
                cursor = position
                current += Array("<a id=\"filepos\(anchors[nextAnchor].filepos)\"></a>".utf8)
                anchorParts[anchors[nextAnchor].filepos] = rawParts.count
                nextAnchor += 1
            }
            let stop = min(end, text.count)
            if cursor < stop {
                current += text[cursor..<stop]
                cursor = stop
            }
        }
        for range in skipped {
            copy(upTo: range.range.lowerBound)
            if range.isPageBreak {
                rawParts.append(current)
                current = []
            }
            cursor = max(cursor, range.range.upperBound)
        }
        // One past the end, so anchors at the very end are placed too.
        copy(upTo: text.count + 1)
        rawParts.append(current)

        // Page breaks in a row leave empty parts, which would show as blank pages.
        var partNumbers: [Int: Int] = [:]
        var kept: [[UInt8]] = []
        for (index, part) in rawParts.enumerated() where Markup.hasContent(part) || (kept.isEmpty && index == rawParts.count - 1) {
            partNumbers[index] = kept.count + 1
            kept.append(part)
        }
        var hrefs: [Int: String] = [:]
        for (filepos, rawPart) in anchorParts {
            if let number = partNumbers[rawPart] {
                hrefs[filepos] = Self.fileName(number) + "#filepos\(filepos)"
            }
        }
        try ReaderError.checkCancellation()

        for (index, part) in kept.enumerated() {
            let href = "text/" + Self.fileName(index + 1)
            let body = rewrite(part, href: href, resources: resources, hrefs: hrefs)
            parts.append(Part(href: href, data: Self.document(title: title, language: language, body: body)))
        }

        if !ncx.isEmpty {
            tableOfContents = TableOfContentsBuilder.links(ncx.compactMap { entry in
                hrefs[entry.position].map { TableOfContentsBuilder.Entry(title: entry.title, href: "text/" + $0, depth: entry.depth) }
            }, mediaType: Self.mediaType)
        } else if let tocGuidePosition {
            tableOfContents = guideTableOfContents(at: tocGuidePosition, skipped: skipped, hrefs: hrefs)
        }
        if tableOfContents.isEmpty {
            warnings.append(PublicationWarning("The book has no table of contents."))
        }
    }

    /// `part0001.html` for part 1.
    static func fileName(_ number: Int) -> String {
        "part\(MOBIResources.name(number)).html"
    }

    /// The value of a `filepos` attribute, which may be zero-padded or quoted.
    static func filepos(in attributes: [Markup.Attribute]) -> Int? {
        guard let value = attributes.first(where: { $0.name == "filepos" })?.value else { return nil }
        return Int(value.prefix { $0.isASCII && $0.isNumber })
    }

    /// The start of the tag that `offset` falls strictly inside, if any.
    private func tagStart(containing offset: Int) -> Int? {
        // Tags are sorted and don't overlap, so a binary search finds the
        // last tag starting before `offset`.
        var low = 0
        var high = tags.count
        while low < high {
            let middle = (low + high) / 2
            if tags[middle].range.lowerBound < offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return nil }
        let tag = tags[low - 1]
        return tag.range.contains(offset) ? tag.range.lowerBound : nil
    }

    /// Markup to leave out: the document's own `html`, `head` and `body`
    /// tags, since each part gets its own, the guide, and page breaks,
    /// which also end a part. In order, without overlaps.
    private func skippedRanges() -> [(range: Range<Int>, isPageBreak: Bool)] {
        var ranges: [(range: Range<Int>, isPageBreak: Bool)] = []
        var skipUntil = 0
        for (index, tag) in tags.enumerated() where tag.range.lowerBound >= skipUntil {
            switch (tag.kind, tag.name) {
            case (.start, "mbp:pagebreak"):
                ranges.append((range: tag.range, isPageBreak: true))
            case (.start, "head"), (.start, "guide"):
                // The whole element goes, up to its end tag.
                let end = tags[(index + 1)...].first { $0.kind == .end && $0.name == tag.name }?.range.upperBound ?? tag.range.upperBound
                ranges.append((range: tag.range.lowerBound..<end, isPageBreak: false))
                skipUntil = end
            case (.start, "html"), (.end, "html"), (.start, "body"), (.end, "body"), (.end, "mbp:pagebreak"):
                ranges.append((range: tag.range, isPageBreak: false))
            case (.other, _) where tag.range.lowerBound < text.count - 1 && Self.isDeclaration(text, at: tag.range.lowerBound):
                ranges.append((range: tag.range, isPageBreak: false))
            default:
                break
            }
        }
        return ranges
    }

    /// Whether the construct at `offset` is a doctype or XML declaration.
    private static func isDeclaration(_ text: [UInt8], at offset: Int) -> Bool {
        Markup.findIgnoringCase(Array("<!doctype".utf8), in: Array(text[offset..<min(text.count, offset + 9)]), from: 0) == 0
            || text[offset...].starts(with: "<?xml".utf8)
    }

    /// The part's markup with images, links and Mobipocket tags rewritten.
    private mutating func rewrite(_ part: [UInt8], href: String, resources: MOBIResources, hrefs: [Int: String]) -> String {
        var output: [UInt8] = []
        output.reserveCapacity(part.count)
        var cursor = 0
        for tag in Markup.tags(in: part) {
            output += part[cursor..<tag.range.lowerBound]
            cursor = tag.range.upperBound
            // Mobipocket's own tags, such as mbp:nu and mbp:section, mean
            // nothing to a browser.
            if tag.name.hasPrefix("mbp:") {
                continue
            }
            guard tag.kind == .start else {
                output += part[tag.range]
                continue
            }
            var attributes = Markup.attributes(of: tag, in: part)
            var changed = false

            let imageAttributes: Set<String> = ["recindex", "hirecindex", "lorecindex"]
            if let index = attributes.firstIndex(where: { imageAttributes.contains($0.name) }) {
                let value = attributes[index].value ?? ""
                if let number = Int(value.prefix { $0.isASCII && $0.isNumber }), let path = resources.path(number) {
                    attributes.removeAll { imageAttributes.contains($0.name) || $0.name == "src" }
                    attributes.append(Markup.Attribute(name: "src", value: "../" + path))
                    changed = true
                } else {
                    warnings.append(PublicationWarning("An image refers to resource \(value), which the book doesn't have.", href: href))
                }
            }

            if let position = Self.filepos(in: attributes) {
                attributes.removeAll { $0.name == "filepos" }
                if let target = hrefs[position] {
                    attributes.removeAll { $0.name == "href" }
                    attributes.append(Markup.Attribute(name: "href", value: target))
                }
                changed = true
            }

            if changed {
                output += Markup.startTag(tag.name, attributes, selfClosing: tag.isSelfClosing)
            } else {
                output += part[tag.range]
            }
        }
        output += part[cursor...]
        return encoding.decode(output)
    }

    /// Entries from the links in the region the guide's `toc` reference
    /// points to, up to the next page break.
    private func guideTableOfContents(at position: Int, skipped: [(range: Range<Int>, isPageBreak: Bool)], hrefs: [Int: String]) -> [Link] {
        let start = tagStart(containing: position) ?? position
        let end = skipped.first { $0.isPageBreak && $0.range.lowerBound > start }?.range.lowerBound ?? text.count
        var entries: [TableOfContentsBuilder.Entry] = []
        let regionTags = tags.filter { $0.range.lowerBound >= start && $0.range.upperBound <= end }
        for (index, tag) in regionTags.enumerated() where tag.kind == .start && tag.name == "a" {
            guard let filepos = Self.filepos(in: Markup.attributes(of: tag, in: text)),
                  let href = hrefs[filepos]
            else { continue }
            let close = regionTags[(index + 1)...].first { $0.kind == .end && $0.name == "a" }?.range.lowerBound ?? tag.range.upperBound
            let title = Self.plainText(Array(text[tag.range.upperBound..<close]), encoding: encoding)
            guard !title.isEmpty else { continue }
            entries.append(TableOfContentsBuilder.Entry(title: title, href: "text/" + href, depth: 0))
        }
        return TableOfContentsBuilder.links(entries, mediaType: Self.mediaType)
    }

    /// The text of some markup: tags removed, common entities decoded and
    /// whitespace collapsed.
    static func plainText(_ markup: [UInt8], encoding: MOBITextEncoding) -> String {
        var bytes: [UInt8] = []
        var cursor = 0
        for tag in Markup.tags(in: markup) {
            bytes += markup[cursor..<tag.range.lowerBound]
            cursor = tag.range.upperBound
        }
        bytes += markup[cursor...]
        var text = encoding.decode(bytes)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacing(entity, with: character)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A minimal HTML document around a part's markup. Parts are served as
    /// HTML rather than XHTML because MOBI 6 markup is rarely well-formed.
    static func document(title: String?, language: String?, body: String) -> Data {
        let lang = language.map { " lang=\"\(XHTML.escape($0))\"" } ?? ""
        let document = """
            <!DOCTYPE html>
            <html\(lang)>
            <head><meta charset="utf-8"><title>\(XHTML.escape(title ?? ""))</title></head>
            <body>
            \(body)
            </body>
            </html>

            """
        return Data(document.utf8)
    }
}
