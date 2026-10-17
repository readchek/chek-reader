public import ChekReaderCore

/// PDF through PDFKit.
///
/// Register it once at launch: `ReaderFormats.register(PDFModule.self)`.
public enum PDFModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.pdf]
}
