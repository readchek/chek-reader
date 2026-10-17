public import ChekReaderCore

/// Plain text and Markdown.
///
/// Register it once at launch: `ReaderFormats.register(TextModule.self)`.
public enum TextModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.plainText, .markdown]
}
