import ChekReaderCore
import Foundation

/// Converts a Markdown file into a publication: a chapter per top-level
/// heading, a table of contents from the headings, and metadata from YAML
/// front matter.
struct MarkdownParser {
    let text: String
    let fileName: String?

    func parse() throws(ReaderError) -> Publication {
        var body = text
        var metadata = Publication.Metadata()
        if let frontMatter = Self.frontMatter(in: text) {
            body = frontMatter.body
            metadata.title = frontMatter.fields["title"]
            if let author = frontMatter.fields["author"] {
                metadata.authors = [Publication.Contributor(name: author)]
            }
            metadata.languages = (frontMatter.fields["lang"] ?? frontMatter.fields["language"]).map { [$0] } ?? []
            metadata.summary = frontMatter.fields["description"]
            metadata.published = frontMatter.fields["date"]
        }
        try ReaderError.checkCancellation()

        var blocks = MarkdownBlockParser.parse(body)
        try ReaderError.checkCancellation()

        // Chapters start at the shallowest heading level that's used more
        // than once, so a document with one title and several sections is
        // split at the sections.
        let levels = blocks.compactMap { block -> Int? in
            if case .heading(let level, _, _) = block { level } else { nil }
        }
        let splitLevel = (1...3).first { level in levels.filter { $0 == level }.count > 1 }
            ?? levels.min()
            ?? 0

        // Give headings ids and decide which chapter each block goes in.
        var slugs = Slugs()
        var chapters: [[MarkdownBlock]] = [[]]
        var headings: [(level: Int, text: String, chapter: Int, id: String)] = []
        for index in blocks.indices {
            if case .heading(let level, let text, _) = blocks[index] {
                let id = slugs.make(from: text)
                blocks[index] = .heading(level: level, text: text, id: id)
                if level <= splitLevel, !chapters[chapters.count - 1].isEmpty {
                    chapters.append([])
                }
                headings.append((level, text, chapters.count - 1, id))
            }
            chapters[chapters.count - 1].append(blocks[index])
        }

        if metadata.title == nil {
            metadata.title = headings.first { $0.level == levels.min() }.map { Self.plain($0.text) }
                ?? TextDecoding.title(fromFileName: fileName)
        }

        let hrefs = chapters.indices.map { String(format: "text/chapter-%04d.xhtml", $0 + 1) }
        let chapterOfID = Dictionary(headings.map { ($0.id, $0.chapter) }, uniquingKeysWith: { first, _ in first })
        var resources: [String: Data] = [TextStyles.path: Data(TextStyles.css.utf8)]
        var readingOrder: [Link] = []
        for (index, chapter) in chapters.enumerated() {
            let inline = MarkdownInline { destination in
                guard destination.hasPrefix("#") else { return destination }
                let id = String(destination.dropFirst())
                guard let target = chapterOfID[id] else { return nil }
                return target == index ? destination : "\(hrefs[target].dropFirst(5))#\(id)"
            }
            let title = headings.first { $0.chapter == index }.map { Self.plain($0.text) } ?? metadata.title
            let html = MarkdownRenderer(inline: inline).render(chapter)
            resources[hrefs[index]] = XHTML.document(
                title: title,
                language: metadata.languages.first,
                body: html,
                stylesheets: ["../" + TextStyles.path]
            )
            readingOrder.append(Link(href: hrefs[index], mediaType: XHTML.mediaType))
        }

        let tableOfContents = Self.nest(headings.filter { $0.level <= max(splitLevel, 1) + 1 }.map {
            (level: $0.level, link: Link(href: "\(hrefs[$0.chapter])#\($0.id)", title: Self.plain($0.text)))
        })

        return Publication(
            format: .markdown,
            metadata: metadata,
            readingOrder: readingOrder,
            tableOfContents: tableOfContents,
            resources: [Link(href: TextStyles.path, mediaType: "text/css")],
            container: MemoryContainer(resources)
        )
    }

    /// Nests entries under the nearest shallower entry before them.
    static func nest(_ entries: [(level: Int, link: Link)]) -> [Link] {
        var index = 0
        func children(deeperThan level: Int) -> [Link] {
            var links: [Link] = []
            while index < entries.count, entries[index].level > level {
                var link = entries[index].link
                let own = entries[index].level
                index += 1
                link.children = children(deeperThan: own)
                links.append(link)
            }
            return links
        }
        return children(deeperThan: 0)
    }

    /// A heading's text without its Markdown, for titles.
    static func plain(_ text: String) -> String {
        var result = ""
        var skipping = false
        for character in text {
            switch character {
            case "*", "_", "`", "~": continue
            case "]": skipping = true
            case "(" where skipping: continue
            case ")" where skipping: skipping = false
            case "[": continue
            default:
                if !skipping || character == " " { result.append(character) }
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Front matter

    /// YAML front matter between `---` lines at the very start. Only simple
    /// `key: value` lines are read.
    static func frontMatter(in text: String) -> (fields: [String: String], body: String)? {
        guard text.hasPrefix("---\n") else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty, !value.isEmpty {
                fields[key] = value
            }
        }
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }
}

/// Makes unique, URL-friendly ids from heading text, as GitHub does.
struct Slugs {
    private var used: [String: Int] = [:]

    mutating func make(from text: String) -> String {
        var slug = ""
        for character in MarkdownParser.plain(text).lowercased() {
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                slug.append(character)
            } else if character == " " {
                slug.append("-")
            }
        }
        if slug.isEmpty || slug.first?.isNumber == true {
            slug = "section-" + slug
        }
        if let count = used[slug] {
            used[slug] = count + 1
            return "\(slug)-\(count)"
        }
        used[slug] = 1
        return slug
    }
}
