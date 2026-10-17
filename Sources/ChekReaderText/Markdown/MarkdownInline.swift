import ChekReaderCore
import Foundation

/// Renders Markdown's inline syntax as XHTML: emphasis, code, links,
/// images, line breaks and escapes. Everything else is escaped text.
struct MarkdownInline {
    /// Rewrites a link's destination, such as `#heading` to the chapter
    /// that has it. Returns `nil` to drop the link and keep its text.
    var resolveLink: (String) -> String? = { $0 }

    /// Emphasis nested deeper than this is left as text.
    private static let maxDepth = 16

    func render(_ text: String) -> String {
        render(Array(text), depth: 0)
    }

    private func render(_ text: [Character], depth: Int) -> String {
        var html = ""
        var index = 0
        while index < text.count {
            let character = text[index]
            switch character {
            case "\\":
                if index + 1 < text.count, text[index + 1] == "\n" {
                    html += "<br/>\n"
                    index += 2
                } else if index + 1 < text.count, text[index + 1].isPunctuation || text[index + 1].isSymbol {
                    html += XHTML.escape(String(text[index + 1]))
                    index += 2
                } else {
                    html += "\\"
                    index += 1
                }

            case "`":
                let run = runLength(text, at: index)
                if let close = findRun(of: "`", length: run, in: text, from: index + run) {
                    var code = String(text[(index + run)..<close]).replacingOccurrences(of: "\n", with: " ")
                    if code.count > 2, code.hasPrefix(" "), code.hasSuffix(" ") {
                        code = String(code.dropFirst().dropLast())
                    }
                    html += "<code>\(XHTML.escape(code))</code>"
                    index = close + run
                } else {
                    html += String(repeating: "`", count: run)
                    index += run
                }

            case "!" where index + 1 < text.count && text[index + 1] == "[":
                if let link = link(in: text, at: index + 1) {
                    // A Markdown file is read on its own, so images it
                    // points at can't be loaded. Its description stands in.
                    let alt = String(text[link.label])
                    if !alt.isEmpty {
                        html += "<span class=\"image\">\(XHTML.escape(alt))</span>"
                    }
                    index = link.end
                } else {
                    html += "!"
                    index += 1
                }

            case "[":
                if let link = link(in: text, at: index) {
                    let label = render(Array(text[link.label]), depth: depth + 1)
                    if let href = resolveLink(link.destination) {
                        let title = link.title.map { " title=\"\(XHTML.escape($0))\"" } ?? ""
                        html += "<a href=\"\(XHTML.escape(href))\"\(title)>\(label)</a>"
                    } else {
                        html += label
                    }
                    index = link.end
                } else {
                    html += "["
                    index += 1
                }

            case "<":
                if let close = text[index...].firstIndex(of: ">"),
                   let url = autolink(String(text[(index + 1)..<close])) {
                    let shown = XHTML.escape(String(text[(index + 1)..<close]))
                    if let href = resolveLink(url) {
                        html += "<a href=\"\(XHTML.escape(href))\">\(shown)</a>"
                    } else {
                        html += shown
                    }
                    index = close + 1
                } else {
                    html += "&lt;"
                    index += 1
                }

            case "*", "_", "~":
                let run = runLength(text, at: index)
                if let match = emphasis(text, at: index, run: run, depth: depth) {
                    let (tag, length, close) = match
                    let inner = render(Array(text[(index + length)..<close]), depth: depth + 1)
                    html += "<\(tag)>\(inner)</\(tag)>"
                    index = close + length
                } else {
                    html += String(repeating: character, count: run)
                    index += run
                }

            case "&":
                let (decoded, length) = entity(text, at: index)
                html += decoded
                index += length

            case "\n":
                // Two trailing spaces make a hard break.
                if html.hasSuffix("  ") {
                    while html.hasSuffix(" ") { html.removeLast() }
                    html += "<br/>\n"
                } else {
                    html += "\n"
                }
                index += 1

            default:
                html += XHTML.escape(String(character))
                index += 1
            }
        }
        return html
    }

    // MARK: - Emphasis

    private func runLength(_ text: [Character], at index: Int) -> Int {
        var end = index
        while end < text.count, text[end] == text[index] {
            end += 1
        }
        return end - index
    }

    /// The tag, delimiter length and closing index for emphasis opening at
    /// `index`, or `nil` when it doesn't open any.
    private func emphasis(_ text: [Character], at index: Int, run: Int, depth: Int) -> (String, Int, Int)? {
        guard depth < Self.maxDepth else { return nil }
        let character = text[index]
        let after = index + run < text.count ? text[index + run] : " "
        guard !after.isWhitespace else { return nil }
        // An underscore inside a word, as in snake_case, isn't emphasis.
        if character == "_", index > 0, text[index - 1].isLetter || text[index - 1].isNumber {
            return nil
        }
        let candidates: [(String, Int)] = switch character {
        case "~": run >= 2 ? [("del", 2)] : []
        default: run >= 2 ? [("strong", 2), ("em", 1)] : [("em", 1)]
        }
        for (tag, length) in candidates {
            if let close = closing(character, length: length, in: text, from: index + length) {
                return (tag, length, close)
            }
        }
        return nil
    }

    /// The next run of exactly `length` delimiters that can close emphasis:
    /// it follows something other than whitespace.
    private func closing(_ character: Character, length: Int, in text: [Character], from start: Int) -> Int? {
        var index = start
        while index < text.count {
            if text[index] == "`" {
                // Delimiters inside code spans don't count.
                let run = runLength(text, at: index)
                index = (findRun(of: "`", length: run, in: text, from: index + run) ?? index) + run
                continue
            }
            guard text[index] == character else {
                index += 1
                continue
            }
            let run = runLength(text, at: index)
            if run == length, index > start, !text[index - 1].isWhitespace {
                let next = index + run
                if character != "_" || next >= text.count || !(text[next].isLetter || text[next].isNumber) {
                    return index
                }
            }
            index += run
        }
        return nil
    }

    private func findRun(of character: Character, length: Int, in text: [Character], from start: Int) -> Int? {
        var index = start
        while index < text.count {
            if text[index] == character {
                let run = runLength(text, at: index)
                if run == length {
                    return index
                }
                index += run
            } else {
                index += 1
            }
        }
        return nil
    }

    // MARK: - Links

    private struct ParsedLink {
        var label: Range<Int>
        var destination: String
        var title: String?
        /// The index after the link.
        var end: Int
    }

    /// An inline link, `[label](destination "title")`, starting at the `[`.
    private func link(in text: [Character], at start: Int) -> ParsedLink? {
        var depth = 0
        var index = start
        var labelEnd: Int?
        while index < text.count {
            switch text[index] {
            case "\\": index += 1
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { labelEnd = index }
            default: break
            }
            if labelEnd != nil { break }
            index += 1
        }
        guard let labelEnd, labelEnd + 1 < text.count, text[labelEnd + 1] == "(" else { return nil }
        guard let close = matchingParenthesis(in: text, from: labelEnd + 1) else { return nil }
        var inside = String(text[(labelEnd + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        var title: String?
        if let quote = inside.last, quote == "\"" || quote == "'",
           let open = inside.dropLast().lastIndex(of: quote),
           open > inside.startIndex, inside[inside.index(before: open)].isWhitespace {
            title = String(inside[inside.index(after: open)..<inside.index(before: inside.endIndex)])
            inside = inside[..<open].trimmingCharacters(in: .whitespaces)
        }
        if inside.hasPrefix("<"), inside.hasSuffix(">") {
            inside = String(inside.dropFirst().dropLast())
        }
        return ParsedLink(label: (start + 1)..<labelEnd, destination: inside, title: title, end: close + 1)
    }

    private func matchingParenthesis(in text: [Character], from open: Int) -> Int? {
        var depth = 0
        var index = open
        while index < text.count {
            switch text[index] {
            case "\\": index += 1
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            case "\n" where depth > 0 && index + 1 < text.count && text[index + 1] == "\n":
                return nil
            default: break
            }
            index += 1
        }
        return nil
    }

    /// The URL of an autolink's contents, such as `https://example.com`
    /// or `someone@example.com`, or `nil` when it isn't one.
    private func autolink(_ contents: String) -> String? {
        guard !contents.isEmpty, !contents.contains(where: { $0.isWhitespace || $0 == "<" }) else { return nil }
        if let colon = contents.firstIndex(of: ":"), contents[..<colon].count >= 2,
           contents[..<colon].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) }) {
            return contents
        }
        if contents.contains("@"), !contents.contains("/") {
            return "mailto:" + contents
        }
        return nil
    }

    // MARK: - Entities

    /// The named entities documents commonly use. XHTML only defines the
    /// five XML ones, so the rest become their characters.
    private static let entities: [String: String] = [
        "amp": "&amp;", "lt": "&lt;", "gt": "&gt;", "quot": "&quot;", "apos": "&#39;",
        "nbsp": "\u{A0}", "copy": "©", "reg": "®", "trade": "™", "mdash": "—", "ndash": "–",
        "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«",
        "raquo": "»", "deg": "°", "times": "×", "middot": "·", "bull": "•", "sect": "§", "para": "¶",
    ]

    /// An entity reference at `index` as XHTML, and how many characters it
    /// took. A lone `&` is escaped.
    private func entity(_ text: [Character], at index: Int) -> (String, Int) {
        var end = index + 1
        while end < text.count, end - index <= 32, text[end].isASCII, text[end].isLetter || text[end].isNumber || text[end] == "#" {
            end += 1
        }
        guard end < text.count, text[end] == ";", end > index + 1 else { return ("&amp;", 1) }
        let name = String(text[(index + 1)..<end])
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            if let value, let scalar = Unicode.Scalar(value), value != 0 {
                return (XHTML.escape(String(Character(scalar))), end - index + 1)
            }
            return ("&amp;", 1)
        }
        if let replacement = Self.entities[name] {
            return (replacement, end - index + 1)
        }
        return ("&amp;", 1)
    }
}
