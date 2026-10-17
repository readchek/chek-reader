/// The stylesheet every converted text document links to. It sets only
/// what plain text and Markdown can't, so the reader's themes and text
/// size still apply.
enum TextStyles {
    static let path = "styles/text.css"

    static let css = """
        body { line-height: 1.5; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
        pre { white-space: pre-wrap; overflow-wrap: anywhere; }
        code, pre { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
        blockquote { margin-inline: 1.5em 0; padding-inline-start: 1em; border-inline-start: 3px solid rgba(128, 128, 128, 0.5); }
        table { border-collapse: collapse; }
        th, td { border: 1px solid rgba(128, 128, 128, 0.5); padding: 0.25em 0.5em; }
        img { max-width: 100%; height: auto; }
        hr { border: none; border-top: 1px solid rgba(128, 128, 128, 0.5); }
        p.plain { margin: 0 0 0.75em; }

        """
}
