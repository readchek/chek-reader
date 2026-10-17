import ChekReaderCore
import Foundation

/// Converts FictionBook body markup to XHTML.
///
/// FictionBook's elements map closely onto HTML's, so each is rendered as
/// its HTML counterpart, with classes from ``FB2Stylesheet`` for those that
/// have none. Elements it doesn't know are dropped but their content kept,
/// so text in extensions or misspelled elements still shows.
struct FB2Renderer {
    /// The generated document each element id is in, as a file name in the
    /// `text/` folder, such as `section-0003.xhtml`.
    var documentForID: [String: String]
    /// The href of each binary's resource from the publication's root, by
    /// binary id.
    var imageForID: [String: String]
    /// The file name of the document being rendered, so links within it
    /// stay fragment-only.
    var currentDocument = ""
    /// Problems found while rendering.
    private(set) var warnings: [PublicationWarning] = []
    private var reportedImages: Set<String> = []

    init(documentForID: [String: String], imageForID: [String: String]) {
        self.documentForID = documentForID
        self.imageForID = imageForID
    }

    /// The XHTML for `nodes`, which are children of a `<body>`.
    ///
    /// - Parameter depth: The section depth `nodes` are at, which sets the
    ///   heading level of their titles.
    mutating func render(_ nodes: [MarkupNode], depth: Int) -> String {
        var out = ""
        for node in nodes {
            render(node, depth: depth, into: &out)
        }
        return out
    }

    /// Renders `node` and its content.
    ///
    /// - Parameter depth: How many sections `node` is inside, which sets
    ///   the heading level of titles.
    private mutating func render(_ node: MarkupNode, depth: Int, into out: inout String) {
        let id = node.attribute("id").map { " id=\"\(XHTML.escape($0))\"" } ?? ""
        switch node.name {
        case "section":
            out += "<section\(id)>"
            renderChildren(of: node, depth: depth + 1, into: &out)
            out += "</section>"
        case "title":
            renderTitle(node, id: id, depth: depth, into: &out)
        case "p":
            wrap(node, in: "p", id: id, depth: depth, into: &out)
        case "subtitle":
            wrap(node, in: "p", class: "subtitle", id: id, depth: depth, into: &out)
        case "text-author":
            wrap(node, in: "p", class: "text-author", id: id, depth: depth, into: &out)
        case "date":
            wrap(node, in: "p", class: "date", id: id, depth: depth, into: &out)
        case "v":
            wrap(node, in: "div", class: "v", id: id, depth: depth, into: &out)
        case "empty-line":
            out += "<p class=\"empty-line\"\(id)></p>"
        case "epigraph":
            wrap(node, in: "blockquote", class: "epigraph", id: id, depth: depth, into: &out)
        case "cite":
            wrap(node, in: "blockquote", class: "cite", id: id, depth: depth, into: &out)
        case "poem", "stanza", "annotation":
            wrap(node, in: "div", class: node.name, id: id, depth: depth, into: &out)
        case "emphasis":
            wrap(node, in: "em", id: id, depth: depth, into: &out)
        case "strong", "sub", "sup", "code":
            wrap(node, in: node.name, id: id, depth: depth, into: &out)
        case "strikethrough":
            wrap(node, in: "del", id: id, depth: depth, into: &out)
        case "style":
            wrap(node, in: "span", id: id, depth: depth, into: &out)
        case "table", "tr":
            wrap(node, in: node.name, id: id, depth: depth, into: &out)
        case "td", "th":
            out += "<\(node.name)\(id)\(spans(of: node))>"
            renderChildren(of: node, depth: depth, into: &out)
            out += "</\(node.name)>"
        case "image":
            renderImage(node, id: id, into: &out)
        case "a":
            renderLink(node, id: id, depth: depth, into: &out)
        default:
            // An unknown element with an id still needs a target for links.
            if !id.isEmpty {
                out += "<span\(id)></span>"
            }
            renderChildren(of: node, depth: depth, into: &out)
        }
    }

    /// Elements that hold only other elements, whose whitespace is just
    /// the book's indentation.
    private static let containers: Set<String> = [
        "section", "title", "epigraph", "cite", "poem", "stanza", "annotation", "table", "tr",
    ]

    private mutating func renderChildren(of node: MarkupNode, depth: Int, into out: inout String) {
        let dropsWhitespace = Self.containers.contains(node.name)
        for child in node.children {
            switch child {
            case .element(let element):
                render(element, depth: depth, into: &out)
            case .text(let text):
                if dropsWhitespace, text.allSatisfy(\.isWhitespace) {
                    continue
                }
                out += XHTML.escape(text)
            }
        }
    }

    private mutating func wrap(_ node: MarkupNode, in tag: String, class className: String? = nil, id: String, depth: Int, into out: inout String) {
        let classAttribute = className.map { " class=\"\($0)\"" } ?? ""
        out += "<\(tag)\(classAttribute)\(id)>"
        renderChildren(of: node, depth: depth, into: &out)
        out += "</\(tag)>"
    }

    /// A title as one heading, with its paragraphs as lines, since HTML
    /// headings can't hold paragraphs.
    private mutating func renderTitle(_ node: MarkupNode, id: String, depth: Int, into out: inout String) {
        let level = min(max(depth, 1), 6)
        out += "<h\(level) class=\"title\"\(id)>"
        var isFirstLine = true
        for child in node.children {
            switch child {
            case .element(let element) where element.name == "p":
                if !isFirstLine {
                    out += "<br/>"
                }
                isFirstLine = false
                if let lineID = element.attribute("id") {
                    out += "<span id=\"\(XHTML.escape(lineID))\"></span>"
                }
                renderChildren(of: element, depth: depth, into: &out)
            case .element(let element) where element.name == "empty-line":
                continue
            case .element(let element):
                render(element, depth: depth, into: &out)
            case .text(let text):
                if !text.allSatisfy(\.isWhitespace) {
                    out += XHTML.escape(text)
                }
            }
        }
        out += "</h\(level)>"
    }

    /// `colspan` and `rowspan` of a table cell, when they're numbers.
    private func spans(of cell: MarkupNode) -> String {
        var result = ""
        for name in ["colspan", "rowspan"] {
            if let value = cell.attribute(name), let span = Int(value), span > 0 {
                result += " \(name)=\"\(span)\""
            }
        }
        return result
    }

    private mutating func renderImage(_ node: MarkupNode, id: String, into out: inout String) {
        let href = node.attribute("href") ?? ""
        let binaryID = href.hasPrefix("#") ? String(href.dropFirst()) : href
        guard let image = imageForID[binaryID] else {
            if reportedImages.insert(href).inserted {
                warnings.append(PublicationWarning("An image refers to \"\(href)\", which isn't a binary in the book. It was left out."))
            }
            return
        }
        let alt = node.attribute("alt") ?? ""
        let title = node.attribute("title").map { " title=\"\(XHTML.escape($0))\"" } ?? ""
        // Documents are in text/, a sibling of the images folder.
        out += "<img\(id) src=\"../\(XHTML.escape(image))\" alt=\"\(XHTML.escape(alt))\"\(title)/>"
    }

    private mutating func renderLink(_ node: MarkupNode, id: String, depth: Int, into out: inout String) {
        var attributes = id
        if let raw = node.attribute("href"), let href = resolve(raw) {
            attributes += " href=\"\(XHTML.escape(href))\""
        }
        if node.attribute("type") == "note" {
            attributes += " class=\"note\" epub:type=\"noteref\""
        }
        out += "<a\(attributes)>"
        renderChildren(of: node, depth: depth, into: &out)
        out += "</a>"
    }

    /// Where a link in the book goes in the generated documents. Links to
    /// ids point at the document the id ended up in; other links are kept
    /// as they are, except scripts, which are dropped.
    private func resolve(_ href: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("javascript:") {
            return nil
        }
        guard trimmed.hasPrefix("#") else { return trimmed }
        let target = String(trimmed.dropFirst())
        guard let document = documentForID[target], document != currentDocument else {
            return trimmed
        }
        return "\(document)#\(target)"
    }
}
