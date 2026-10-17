import Foundation

/// Splits Markdown into blocks, following CommonMark and the GitHub table
/// extension closely enough for real documents.
///
/// Raw HTML isn't passed through: an HTML block keeps only its text, so a
/// document can't add scripts or markup the reader didn't expect.
enum MarkdownBlockParser {
    /// Containers nested deeper than this are read as plain paragraphs, so
    /// a hostile document can't recurse without bound.
    static let maxDepth = 32

    static func parse(_ text: String) -> [MarkdownBlock] {
        parse(text.split(separator: "\n", omittingEmptySubsequences: false), depth: 0)
    }

    static func parse(_ lines: [Substring], depth: Int) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if isBlank(line) {
                index += 1
                continue
            }
            let indent = indentation(of: line)
            let content = stripIndentation(line, upTo: 3)

            // Indented code.
            if indent >= 4 {
                var code: [Substring] = []
                while index < lines.count, isBlank(lines[index]) || indentation(of: lines[index]) >= 4 {
                    code.append(stripIndentation(lines[index], upTo: 4))
                    index += 1
                }
                while let last = code.last, isBlank(last) {
                    code.removeLast()
                }
                blocks.append(.code(language: nil, text: code.joined(separator: "\n")))
                continue
            }

            // Fenced code.
            if let fence = fence(content) {
                var code: [Substring] = []
                index += 1
                while index < lines.count {
                    let candidate = stripIndentation(lines[index], upTo: 3)
                    if candidate.hasPrefix(String(repeating: fence.character, count: fence.length)),
                       candidate.allSatisfy({ $0 == fence.character || $0 == " " || $0 == "\t" }) {
                        index += 1
                        break
                    }
                    code.append(stripIndentation(lines[index], upTo: indent))
                    index += 1
                }
                blocks.append(.code(language: fence.info, text: code.joined(separator: "\n")))
                continue
            }

            if let heading = atxHeading(content) {
                blocks.append(.heading(level: heading.level, text: heading.text, id: nil))
                index += 1
                continue
            }

            if isThematicBreak(content) {
                blocks.append(.rule)
                index += 1
                continue
            }

            if content.hasPrefix(">") {
                var quoted: [Substring] = []
                while index < lines.count, !isBlank(lines[index]) {
                    let candidate = stripIndentation(lines[index], upTo: 3)
                    if candidate.hasPrefix(">") {
                        var rest = candidate.dropFirst()
                        if rest.first == " " { rest = rest.dropFirst() }
                        quoted.append(rest)
                    } else if quoted.last.map({ !isBlank($0) }) == true, !startsBlock(candidate) {
                        // A lazy continuation of the quoted paragraph.
                        quoted.append(candidate)
                    } else {
                        break
                    }
                    index += 1
                }
                blocks.append(depth < maxDepth ? .quote(parse(quoted, depth: depth + 1)) : .paragraph(quoted.joined(separator: "\n")))
                continue
            }

            if let marker = listMarker(content) {
                let (list, next) = parseList(lines, from: index, first: marker, depth: depth)
                blocks.append(list)
                index = next
                continue
            }

            if index + 1 < lines.count, content.contains("|"), let alignments = tableDelimiter(lines[index + 1]) {
                let header = cells(content)
                if header.count == alignments.count {
                    var rows: [[String]] = []
                    index += 2
                    while index < lines.count, !isBlank(lines[index]), lines[index].contains("|") {
                        var row = cells(stripIndentation(lines[index], upTo: 3))
                        row = Array(row.prefix(header.count)) + Array(repeating: "", count: max(0, header.count - row.count))
                        rows.append(row)
                        index += 1
                    }
                    blocks.append(.table(header: header, alignments: alignments, rows: rows))
                    continue
                }
            }

            if content.hasPrefix("<"), let second = content.dropFirst().first, second.isLetter || second == "/" || second == "!" {
                var html: [Substring] = []
                while index < lines.count, !isBlank(lines[index]) {
                    html.append(lines[index])
                    index += 1
                }
                let text = textOfHTML(html.joined(separator: "\n"))
                if !text.isEmpty {
                    blocks.append(.paragraph(text))
                }
                continue
            }

            // A paragraph, which a setext underline turns into a heading.
            var paragraph: [Substring] = [content]
            index += 1
            while index < lines.count, !isBlank(lines[index]) {
                let candidate = stripIndentation(lines[index], upTo: 3)
                if let level = setextLevel(candidate) {
                    blocks.append(.heading(level: level, text: paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces), id: nil))
                    paragraph = []
                    index += 1
                    break
                }
                if indentation(of: lines[index]) < 4, startsBlock(candidate) {
                    break
                }
                paragraph.append(candidate)
                index += 1
            }
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            }
        }
        return blocks
    }

    // MARK: - Lists

    struct ListMarker {
        var ordered: Bool
        var start: Int
        /// `-`, `*`, `+`, `.` or `)`, which must match for items to share a list.
        var delimiter: Character
        /// The columns before the item's content: the marker and its spaces.
        var width: Int
    }

    static func listMarker(_ content: Substring) -> ListMarker? {
        guard let first = content.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let rest = content.dropFirst()
            guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
            let spaces = rest.prefix { $0 == " " }.count
            return ListMarker(ordered: false, start: 1, delimiter: first, width: 1 + (rest.isEmpty || spaces > 4 ? 1 : spaces))
        }
        let digits = content.prefix { $0.isASCII && $0.isNumber }
        guard (1...9).contains(digits.count), let start = Int(digits) else { return nil }
        let rest = content.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
        let after = rest.dropFirst()
        guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
        let spaces = after.prefix { $0 == " " }.count
        return ListMarker(ordered: true, start: start, delimiter: delimiter, width: digits.count + 1 + (after.isEmpty || spaces > 4 ? 1 : spaces))
    }

    private static func parseList(_ lines: [Substring], from start: Int, first: ListMarker, depth: Int) -> (MarkdownBlock, Int) {
        var items: [[MarkdownBlock]] = []
        var tight = true
        var index = start
        var marker = first
        while true {
            let indent = indentation(of: lines[index])
            let contentIndent = indent + marker.width
            var itemLines: [Substring] = [Substring(stripIndentation(lines[index], upTo: indent).dropFirst(marker.width))]
            index += 1
            var sawBlank = false
            while index < lines.count {
                let line = lines[index]
                if isBlank(line) {
                    itemLines.append("")
                    sawBlank = true
                    index += 1
                    continue
                }
                if indentation(of: line) >= contentIndent {
                    if sawBlank { tight = false }
                    itemLines.append(stripIndentation(line, upTo: contentIndent))
                    sawBlank = false
                    index += 1
                    continue
                }
                let candidate = stripIndentation(line, upTo: 3)
                if !sawBlank, !startsBlock(candidate), listMarker(candidate) == nil {
                    // A lazy continuation of the item's paragraph.
                    itemLines.append(candidate)
                    index += 1
                    continue
                }
                break
            }
            while let last = itemLines.last, isBlank(last) {
                itemLines.removeLast()
            }
            items.append(depth < maxDepth ? parse(itemLines, depth: depth + 1) : [.paragraph(itemLines.joined(separator: "\n"))])

            guard index < lines.count, indentation(of: lines[index]) < contentIndent,
                  let next = listMarker(stripIndentation(lines[index], upTo: 3)),
                  next.ordered == first.ordered, next.delimiter == first.delimiter
            else { break }
            if sawBlank { tight = false }
            marker = next
        }
        return (.list(ordered: first.ordered, start: first.start, items: items, tight: tight), index)
    }

    // MARK: - Lines

    static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// The line's leading whitespace in columns, with tabs to the next multiple of four.
    static func indentation(of line: Substring) -> Int {
        var columns = 0
        for character in line {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += 4 - columns % 4
            } else {
                break
            }
        }
        return columns
    }

    /// The line without up to `columns` columns of leading whitespace.
    static func stripIndentation(_ line: Substring, upTo columns: Int) -> Substring {
        var removed = 0
        var index = line.startIndex
        while index < line.endIndex, removed < columns {
            let character = line[index]
            if character == " " {
                removed += 1
            } else if character == "\t" {
                removed += 4 - removed % 4
            } else {
                break
            }
            index = line.index(after: index)
        }
        return line[index...]
    }

    /// Whether a line would start a block other than a paragraph, and so
    /// interrupts one.
    private static func startsBlock(_ content: Substring) -> Bool {
        if content.hasPrefix(">") || fence(content) != nil || atxHeading(content) != nil || isThematicBreak(content) {
            return true
        }
        if let marker = listMarker(content) {
            // An empty item or one not starting at 1 can't interrupt a paragraph.
            let rest = content.dropFirst(marker.width)
            return !isBlank(rest) && (!marker.ordered || marker.start == 1)
        }
        return false
    }

    private static func fence(_ content: Substring) -> (character: Character, length: Int, info: String?)? {
        guard let character = content.first, character == "`" || character == "~" else { return nil }
        let length = content.prefix { $0 == character }.count
        guard length >= 3 else { return nil }
        let info = content.dropFirst(length).trimmingCharacters(in: .whitespaces)
        if character == "`", info.contains("`") {
            return nil
        }
        let language = info.split(separator: " ").first.map(String.init)
        return (character, length, language)
    }

    private static func atxHeading(_ content: Substring) -> (level: Int, text: String)? {
        let level = content.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = content.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of #s, after a space, isn't part of the heading.
        let trailing = text.reversed().prefix { $0 == "#" }.count
        if trailing > 0 {
            let without = text.dropLast(trailing)
            if without.isEmpty || without.last == " " {
                text = without.trimmingCharacters(in: .whitespaces)
            }
        }
        return (level, text)
    }

    private static func isThematicBreak(_ content: Substring) -> Bool {
        let marks = content.filter { $0 != " " && $0 != "\t" }
        guard let first = marks.first, first == "-" || first == "*" || first == "_" else { return false }
        return marks.count >= 3 && marks.allSatisfy { $0 == first }
    }

    private static func setextLevel(_ content: Substring) -> Int? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "=" || first == "-", trimmed.allSatisfy({ $0 == first }) else {
            return nil
        }
        return first == "=" ? 1 : 2
    }

    // MARK: - Tables

    private static func tableDelimiter(_ line: Substring) -> [MarkdownBlock.Alignment?]? {
        let row = cells(stripIndentation(line, upTo: 3))
        guard !row.isEmpty, line.contains("-") else { return nil }
        var alignments: [MarkdownBlock.Alignment?] = []
        for cell in row {
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            alignments.append(left && right ? .center : right ? .right : left ? .left : nil)
        }
        return alignments
    }

    /// The cells of a table row, without the outer pipes. A pipe escaped
    /// with a backslash stays in its cell.
    private static func cells(_ line: Substring) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)[...]
        if trimmed.hasPrefix("|") { trimmed = trimmed.dropFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed = trimmed.dropLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                current.append(character == "|" ? "|" : "\\" + String(character))
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: - HTML

    /// The text of an HTML block, without its tags and comments.
    private static func textOfHTML(_ html: String) -> String {
        var text = ""
        var inTag = false
        var rest = html[...]
        while let character = rest.first {
            if !inTag, rest.hasPrefix("<!--") {
                guard let end = rest.range(of: "-->") else { break }
                rest = rest[end.upperBound...]
                continue
            }
            if character == "<" {
                inTag = true
            } else if character == ">", inTag {
                inTag = false
                text += " "
            } else if !inTag {
                text.append(character)
            }
            rest = rest.dropFirst()
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
