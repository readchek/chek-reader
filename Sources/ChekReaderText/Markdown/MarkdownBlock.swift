/// A block of a Markdown document.
indirect enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String, id: String?)
    case paragraph(String)
    case code(language: String?, text: String)
    case quote([MarkdownBlock])
    case list(ordered: Bool, start: Int, items: [[MarkdownBlock]], tight: Bool)
    case table(header: [String], alignments: [Alignment?], rows: [[String]])
    case rule

    enum Alignment: String, Sendable {
        case left, center, right
    }
}
