public import ChekReaderCore

/// FictionBook, plain and zipped.
///
/// Register it once at launch: `ReaderFormats.register(FB2Module.self)`.
public enum FB2Module: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.fb2, .fb2Zip]
}
