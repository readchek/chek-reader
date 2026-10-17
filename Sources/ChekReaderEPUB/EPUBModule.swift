public import ChekReaderCore

/// Opens EPUB 2 and 3 publications.
///
/// Register it once at launch, or use `ReaderFormats.registerDefaults()`
/// from the `ChekReader` umbrella:
///
/// ```swift
/// ReaderFormats.register(EPUBModule.self)
/// let publication = try await Publication.open(.file(url))
/// ```
///
/// Local files, in-memory data, HTTP URLs and ``ResourceProvider`` sources
/// open. From a URL, only the parts of the book being read are downloaded,
/// using range requests. A provider is trusted to return decrypted resources, so its publications
/// skip the DRM check.
public enum EPUBModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.epub]

    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        let container: any PublicationContainer
        var checksEncryption = true
        switch source {
        case .file(let url):
            container = try ZIPArchive(contentsOf: url, limits: limits)
        case .data(let data, _):
            container = try ZIPArchive(data: data, limits: limits)
        case .provider(let provider):
            container = ProviderContainer(provider: provider, limits: limits)
            checksEncryption = false
        case .remote(let url, let options):
            container = try await RemoteZIPArchive.open(url, options: options, limits: limits)
        case .pages:
            throw .unsupportedFormat(fileName: nil)
        }
        var parser = EPUBParser(container: container, limits: limits, checksEncryption: checksEncryption)
        return try await parser.parse()
    }
}
