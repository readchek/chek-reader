public import ChekReaderCore

/// DRM-free MOBI and AZW3 (KF8).
///
/// Register it once at launch: `ReaderFormats.register(MOBIModule.self)`.
public enum MOBIModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.mobi, .azw3]
}
