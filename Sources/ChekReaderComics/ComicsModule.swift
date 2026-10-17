public import ChekReaderCore

/// Comic book archives (CBZ and CBT) and webtoons.
///
/// Register it once at launch: `ReaderFormats.register(ComicsModule.self)`.
public enum ComicsModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.cbz, .cbt]
}
