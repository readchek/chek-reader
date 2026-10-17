public import ChekReaderCore

/// EPUB 2 and 3, reflowable and fixed layout.
///
/// Register it once at launch: `ReaderFormats.register(EPUBModule.self)`.
public enum EPUBModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.epub]
}
