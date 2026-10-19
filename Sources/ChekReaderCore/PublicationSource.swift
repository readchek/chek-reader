public import Foundation
#if canImport(FoundationNetworking)
public import FoundationNetworking
#endif

/// Where a publication's bytes come from.
public enum PublicationSource: Sendable {
    /// A file on disk.
    case file(URL)
    /// A publication already in memory.
    case data(Data, fileName: String? = nil)
    /// A publication on an HTTP server.
    ///
    /// ZIP-based formats are read with Range requests, entry by entry, so
    /// the first page opens without downloading the whole file.
    case remote(URL, RemoteOptions = RemoteOptions())
    /// Resources supplied by the app, for example decrypted or cached ones.
    case provider(any ResourceProvider)
    /// Page images supplied one at a time, for servers that stream pages.
    case pages(any PageSource)
}

/// Settings for ``PublicationSource/remote(_:_:)``.
public struct RemoteOptions: Sendable {
    /// Adds credentials or headers to each request, refreshing tokens as
    /// needed. The package never stores credentials.
    public var authorize: @Sendable (URLRequest) async throws -> URLRequest
    /// A stable identifier for the publication, used for positions and the
    /// cache. Defaults to the URL.
    public var identifier: String?
    /// Sends each request and returns the response. Defaults to
    /// `URLSession.shared`; supply your own to use another session or to
    /// serve requests in tests.
    public var load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        identifier: String? = nil,
        authorize: @escaping @Sendable (URLRequest) async throws -> URLRequest = { $0 },
        load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.identifier = identifier
        self.authorize = authorize
        self.load = load
    }
}

/// Supplies a publication's resources by path.
public protocol ResourceProvider: Sendable {
    /// The publication's format, when the provider knows it.
    var format: ReaderFormat? { get }
    /// The bytes of the resource at `href`, relative to the publication.
    ///
    /// Formats that keep the whole publication in one file, such as PDF,
    /// plain text, FB2 and MOBI, ask for the whole file with
    /// ``PublicationSource/wholePublicationHref``, an empty href.
    func data(at href: String) async throws -> Data
}

/// Supplies page images one at a time.
public protocol PageSource: Sendable {
    /// How many pages the publication has.
    func pageCount() async throws -> Int
    /// The encoded image for the page at a 0-based index.
    func page(at index: Int) async throws -> Data
    /// The direction pages advance in, when the source knows it, such as
    /// right to left for manga. Pages have no metadata of their own to say.
    var readingProgression: Publication.ReadingProgression { get }
}

extension PageSource {
    public var readingProgression: Publication.ReadingProgression { .auto }
}
