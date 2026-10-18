public import ChekReaderCore

/// Plain text and Markdown.
///
/// Register it once at launch: `ReaderFormats.register(TextModule.self)`.
///
/// Both are converted to XHTML when they open and read in the same
/// navigator as EPUB, so text size, themes and page turns work the same.
/// Plain text is split into chapters at headings such as "Chapter 3", and
/// Markdown at its top-level headings, which also make the table of
/// contents. Text can be UTF-8, UTF-16 with a byte order mark, or
/// Windows-1252. Markdown's raw HTML is reduced to its text, and images it
/// points at show their description, since the file is read on its own.
public enum TextModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.plainText, .markdown]

    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        let data = try await source.wholeFile(limits: limits)
        try ReaderError.checkCancellation()
        let text = TextDecoding.decode(data)
        if format == .markdown {
            return try MarkdownParser(text: text, fileName: source.fileName).parse()
        }
        return try PlainTextParser(text: text, fileName: source.fileName).parse()
    }
}
