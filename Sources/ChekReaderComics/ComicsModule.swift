public import ChekReaderCore
import Foundation

/// Comic book archives (CBZ and CBT) and pages streamed by the app.
///
/// Register it once at launch: `ReaderFormats.register(ComicsModule.self)`.
///
/// Pages are the archive's images in natural order, and `ComicInfo.xml`
/// supplies the title, credits, cover, bookmarks and manga reading
/// direction. A CBZ opens from a URL with range requests, so only the
/// pages being read are downloaded. A CBT is downloaded whole, and a
/// resource provider returns the whole archive for
/// ``PublicationSource/wholePublicationHref``. A ``PageSource`` serves
/// pages one at a time, for servers that stream them.
public enum ComicsModule: ReaderFormatModule {
    public static let formats: [ReaderFormat] = [.cbz, .cbt]

    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        let container: any PublicationContainer
        switch (source, format) {
        case (.pages(let pages), _):
            return try await ComicParser.parse(pages: pages, limits: limits)
        case (.file(let url), .cbz):
            container = try ZIPArchive(contentsOf: url, limits: limits)
        case (.data(let data, _), .cbz):
            container = try ZIPArchive(data: data, limits: limits)
        case (.remote(let url, let options), .cbz):
            container = try await RemoteZIPArchive.open(url, options: options, limits: limits)
        case (_, .cbz):
            container = try ZIPArchive(data: await source.wholeFile(limits: limits), limits: limits)
        case (_, .cbt):
            container = try TARArchive(data: await source.wholeFile(limits: limits), limits: limits)
        default:
            throw .unsupportedFormat(fileName: source.fileName)
        }
        try ReaderError.checkCancellation()
        return try await ComicParser(container: container, format: format, limits: limits, fileName: source.fileName).parse()
    }
}
