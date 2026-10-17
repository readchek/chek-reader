public import ChekReaderCore

/// Optional CBR and CB7 support. Not part of the umbrella product, because it will link libarchive.
///
/// Register it once at launch: `ReaderFormats.register(ArchivesModule.self)`.
public enum ArchivesModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.cbr, .cb7]
}
