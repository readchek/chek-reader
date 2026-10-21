public import ChekReaderCore
import ChekReaderComics

/// Comic book archives in RAR (CBR) and 7-Zip (CB7), read with libarchive.
///
/// Not part of the umbrella product, because it links libarchive: on Apple
/// platforms a prebuilt static XCFramework, and on Linux the system library.
/// Register it once at launch: `ReaderFormats.register(ArchivesModule.self)`.
///
/// Pages and `ComicInfo.xml` are read the same way as in CBZ. The archive
/// is downloaded or read whole, since neither format can be read by range,
/// and a resource provider returns it for
/// ``PublicationSource/wholePublicationHref``. Password-protected archives
/// fail with ``ReaderError/drmProtected(scheme:)``.
public enum ArchivesModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.cbr, .cb7]

    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        guard formats.contains(format) else {
            throw .unsupportedFormat(fileName: source.fileName)
        }
        let data = try await source.wholeFile(limits: limits)
        try ReaderError.checkCancellation()
        let container = try LibArchiveContainer(data: data, format: format, limits: limits)
        try ReaderError.checkCancellation()
        return try await ComicParser(container: container, format: format, limits: limits, fileName: source.fileName).parse()
    }
}
