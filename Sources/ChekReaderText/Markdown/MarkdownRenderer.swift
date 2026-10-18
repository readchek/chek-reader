import ChekReaderCore

/// Renders Markdown blocks as XHTML.
struct MarkdownRenderer {
    var inline: MarkdownInline

    func render(_ blocks: [MarkdownBlock]) -> String {
        blocks.map(render).joined(separator: "\n")
    }

    private func render(_ block: MarkdownBlock) -> String {
        switch block {
        case .heading(let level, let text, let id):
            let anchor = id.map { " id=\"\(XHTML.escape($0))\"" } ?? ""
            return "<h\(level)\(anchor)>\(inline.render(text))</h\(level)>"
        case .paragraph(let text):
            return "<p>\(inline.render(text))</p>"
        case .code(let language, let text):
            let type = language.map { " class=\"language-\(XHTML.escape($0))\"" } ?? ""
            return "<pre><code\(type)>\(XHTML.escape(text))</code></pre>"
        case .quote(let blocks):
            return "<blockquote>\n\(render(blocks))\n</blockquote>"
        case .list(let ordered, let start, let items, let tight):
            let tag = ordered ? "ol" : "ul"
            let startAttribute = ordered && start != 1 ? " start=\"\(start)\"" : ""
            let rendered = items.map { item in
                if tight {
                    // Tight lists show their paragraphs without spacing.
                    let parts = item.map { block -> String in
                        if case .paragraph(let text) = block { inline.render(text) } else { render(block) }
                    }
                    return "<li>\(parts.joined(separator: "\n"))</li>"
                }
                return "<li>\(render(item))</li>"
            }
            return "<\(tag)\(startAttribute)>\n\(rendered.joined(separator: "\n"))\n</\(tag)>"
        case .table(let header, let alignments, let rows):
            func cell(_ tag: String, _ text: String, _ column: Int) -> String {
                let alignment = alignments.indices.contains(column) ? alignments[column] : nil
                let style = alignment.map { " style=\"text-align: \($0.rawValue)\"" } ?? ""
                return "<\(tag)\(style)>\(inline.render(text))</\(tag)>"
            }
            let head = header.enumerated().map { cell("th", $0.element, $0.offset) }.joined()
            let body = rows.map { row in
                "<tr>" + row.enumerated().map { cell("td", $0.element, $0.offset) }.joined() + "</tr>"
            }
            return "<table>\n<thead><tr>\(head)</tr></thead>\n<tbody>\n\(body.joined(separator: "\n"))\n</tbody>\n</table>"
        case .rule:
            return "<hr/>"
        }
    }
}
