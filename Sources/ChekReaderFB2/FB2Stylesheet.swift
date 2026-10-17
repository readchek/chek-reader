import Foundation

/// The stylesheet every generated document links to, for the FictionBook
/// elements HTML has no presentation for.
enum FB2Stylesheet {
    /// The stylesheet's href from the publication's root.
    static let href = "styles/fb2.css"

    static let data = Data("""
        .title { text-align: center; }
        .subtitle { text-align: center; font-weight: bold; }
        .empty-line { margin: 0; min-height: 1em; }
        .epigraph { margin: 1em 0 1em auto; max-width: 70%; text-align: end; font-style: italic; }
        .cite { margin: 1em 2em; }
        .poem { margin: 1em 2em; }
        .stanza { margin: 1em 0; }
        .v { margin: 0; }
        .text-author { text-align: end; font-style: italic; }
        .date { text-align: end; }
        img { max-width: 100%; height: auto; }
        a.note { vertical-align: super; font-size: 0.75em; line-height: 0; }
        table { border-collapse: collapse; }
        td, th { border: 1px solid currentColor; padding: 0.25em; }

        """.utf8)
}
