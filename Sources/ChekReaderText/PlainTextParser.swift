import ChekReaderCore
import Foundation

/// Converts a plain text file into a publication.
///
/// Chapter headings such as "Chapter 12" or "PART TWO" split the text into
/// chapters and make the table of contents. Text without them is split at
/// paragraph breaks into parts of about ``partLength`` characters, so no
/// single page has to lay out a whole book. Project Gutenberg's `Title:`
/// and `Author:` lines become metadata.
struct PlainTextParser {
    let text: String
    let fileName: String?

    /// The characters in a part, when the text has no chapter headings.
    static let partLength = 50_000

    func parse() throws(ReaderError) -> Publication {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let paragraphs = Self.paragraphs(lines)
        try ReaderError.checkCancellation()

        var metadata = Self.metadata(lines.prefix(200))
        if metadata.title == nil {
            metadata.title = TextDecoding.title(fromFileName: fileName)
        }

        // Each chapter: its heading, if it has one, and its paragraphs.
        var chapters: [(title: String?, paragraphs: [String])] = []
        let headings = paragraphs.indices.filter { Self.isHeading(paragraphs[$0]) }
        if headings.count >= 2 {
            let headingSet = Set(headings)
            // Text before the first heading, such as a title page, is a chapter of its own.
            let starts = (headings[0] > 0 ? [0] : []) + headings
            for (offset, start) in starts.enumerated() {
                let end = offset + 1 < starts.count ? starts[offset + 1] : paragraphs.count
                let isHeading = headingSet.contains(start)
                chapters.append((isHeading ? paragraphs[start] : nil, Array(paragraphs[(isHeading ? start + 1 : start)..<end])))
            }
        } else {
            var part: [String] = []
            var length = 0
            for paragraph in paragraphs {
                part.append(paragraph)
                length += paragraph.count
                if length >= Self.partLength {
                    chapters.append((nil, part))
                    part = []
                    length = 0
                }
            }
            if !part.isEmpty || chapters.isEmpty {
                chapters.append((nil, part))
            }
        }

        var resources: [String: Data] = [TextStyles.path: Data(TextStyles.css.utf8)]
        var readingOrder: [Link] = []
        var tableOfContents: [Link] = []
        for (index, chapter) in chapters.enumerated() {
            try ReaderError.checkCancellation()
            let href = String(format: "text/part-%04d.xhtml", index + 1)
            var body = ""
            if let title = chapter.title {
                body += "<h2 id=\"chapter\">\(XHTML.escape(title))</h2>\n"
                tableOfContents.append(Link(href: href, title: title))
            }
            for paragraph in chapter.paragraphs {
                body += "<p class=\"plain\">\(XHTML.escape(paragraph).replacingOccurrences(of: "\n", with: "<br/>\n"))</p>\n"
            }
            resources[href] = XHTML.document(
                title: chapter.title ?? metadata.title,
                language: nil,
                body: body,
                stylesheets: ["../" + TextStyles.path]
            )
            readingOrder.append(Link(href: href, mediaType: XHTML.mediaType))
        }

        return Publication(
            format: .plainText,
            metadata: metadata,
            readingOrder: readingOrder,
            tableOfContents: tableOfContents,
            resources: [Link(href: TextStyles.path, mediaType: "text/css")],
            container: MemoryContainer(resources)
        )
    }

    /// The text's paragraphs.
    ///
    /// Text with blank lines between paragraphs is usually wrapped at a
    /// fixed width, so its lines are joined into flowing paragraphs. Text
    /// without blank lines has a paragraph per line.
    static func paragraphs(_ lines: [Substring]) -> [String] {
        let blank = lines.filter { $0.allSatisfy(\.isWhitespace) }.count
        let separatedByBlankLines = blank * 10 >= lines.count
        var paragraphs: [String] = []
        var current: [Substring] = []
        func flush() {
            if !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if separatedByBlankLines {
                current.append(trimmed[...])
            } else {
                paragraphs.append(trimmed)
            }
        }
        flush()
        return paragraphs
    }

    /// Whether a paragraph looks like a chapter heading: short, on its own,
    /// and starting with a word such as "Chapter" or a Roman numeral.
    static func isHeading(_ paragraph: String) -> Bool {
        guard paragraph.count <= 80, !paragraph.contains("\n") else { return false }
        let words = paragraph.split(whereSeparator: { $0 == " " || $0 == "." || $0 == ":" })
        guard let first = words.first?.lowercased() else { return false }
        if ["chapter", "part", "book", "prologue", "epilogue", "preface", "introduction", "volume", "act"].contains(first) {
            return words.count <= 12
        }
        // A Roman numeral alone, as some novels number their chapters.
        return words.count == 1 && first.count <= 7 && first.allSatisfy { "ivxlc".contains($0) }
    }

    /// Project Gutenberg's header fields.
    static func metadata(_ lines: ArraySlice<Substring>) -> Publication.Metadata {
        var metadata = Publication.Metadata()
        for line in lines {
            if let value = field("Title", in: line) {
                metadata.title = metadata.title ?? value
            } else if let value = field("Author", in: line) {
                metadata.authors = metadata.authors.isEmpty ? [Publication.Contributor(name: value)] : metadata.authors
            } else if let value = field("Language", in: line), metadata.languages.isEmpty {
                metadata.languages = [value == "English" ? "en" : value]
            }
        }
        return metadata
    }

    private static func field(_ name: String, in line: Substring) -> String? {
        guard line.hasPrefix(name + ":") else { return nil }
        let value = line.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
