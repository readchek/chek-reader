public import Foundation

/// A parsed, immutable publication: its metadata, reading order,
/// navigation and resources.
///
/// Opening parses the publication's structure without rendering anything,
/// so it works the same in an app, a command-line tool or a server.
///
/// ```swift
/// let publication = try await Publication.open(.file(url))
/// print(publication.metadata.title ?? "Untitled")
/// for chapter in publication.readingOrder {
///     let html = try await publication.data(at: chapter.href)
/// }
/// ```
public struct Publication: Sendable {
    /// The publication's format.
    public let format: ReaderFormat
    /// Bibliographic and presentation details.
    public let metadata: Metadata
    /// The content documents in reading order.
    public let readingOrder: [Link]
    /// The table of contents, nested as the publication nests it.
    public let tableOfContents: [Link]
    /// Locations of the print edition's pages, when the publication lists them.
    public let pageList: [Link]
    /// Key places such as the cover, the start of the text and the index.
    public let landmarks: [Link]
    /// Every other resource, such as stylesheets, images and fonts.
    public let resources: [Link]
    /// Problems that were repaired or skipped while opening.
    public let warnings: [PublicationWarning]

    private let container: any PublicationContainer

    package init(
        format: ReaderFormat,
        metadata: Metadata,
        readingOrder: [Link],
        tableOfContents: [Link] = [],
        pageList: [Link] = [],
        landmarks: [Link] = [],
        resources: [Link] = [],
        warnings: [PublicationWarning] = [],
        container: any PublicationContainer
    ) {
        self.format = format
        self.metadata = metadata
        self.readingOrder = readingOrder
        self.tableOfContents = tableOfContents
        self.pageList = pageList
        self.landmarks = landmarks
        self.resources = resources
        self.warnings = warnings
        self.container = container
    }

    /// Opens and parses a publication.
    ///
    /// The format is detected from the content, and the module registered
    /// for it with ``ReaderFormats`` does the parsing.
    ///
    /// - Throws: ``ReaderError/formatNotIncluded(_:)`` when the format's
    ///   product isn't registered, ``ReaderError/drmProtected(scheme:)`` for
    ///   DRM, ``ReaderError/limitExceeded(_:)`` when the publication is
    ///   larger than `limits` allow, and ``ReaderError/cancelled`` when the
    ///   task is cancelled.
    public static func open(_ source: PublicationSource, limits: ReaderLimits = .default) async throws(ReaderError) -> Publication {
        try ReaderError.checkCancellation()
        guard let format = try await FormatSniffer.format(of: source) else {
            throw .unsupportedFormat(fileName: source.fileName)
        }
        let module = try ReaderFormats.module(for: format)
        return try await module.open(source, format: format, limits: limits)
    }

    /// Every link in the publication: the reading order, then other resources.
    public var allLinks: [Link] {
        readingOrder + resources
    }

    /// The link for a resource path, ignoring any fragment.
    public func link(for href: String) -> Link? {
        let path = Link(href: href).path
        return allLinks.first { $0.path == path }
    }

    /// The cover image, when the publication names one.
    public var cover: Link? {
        allLinks.first { $0.rels.contains("cover") }
    }

    /// The bytes of the resource at `href`. Any fragment is ignored.
    ///
    /// Obfuscated fonts come back de-obfuscated, ready to use.
    public func data(at href: String) async throws(ReaderError) -> Data {
        try ReaderError.checkCancellation()
        return try await container.data(at: Link(href: href).path)
    }

    /// The size of the resource at `path` in bytes, reading it only when
    /// the container can't say without reading.
    package func length(of path: String) async throws(ReaderError) -> Int64 {
        if let length = await container.length(of: path) {
            return length
        }
        return Int64(try await data(at: path).count)
    }
}

extension Publication {
    /// A position at the start of `link`, or at its fragment if it has one.
    ///
    /// Returns `nil` when the link's resource isn't in the reading order.
    public func locator(for link: Link) -> Locator? {
        let path = link.path
        guard let resource = readingOrder.first(where: { $0.path == path }) else { return nil }
        var fragments: [String] = []
        if let hash = link.href.firstIndex(of: "#") {
            fragments = [String(link.href[link.href.index(after: hash)...])]
        }
        return Locator(
            href: path,
            mediaType: resource.mediaType ?? MediaType.forPath(path),
            title: link.title ?? title(forPath: path, in: tableOfContents),
            locations: Locator.Locations(fragments: fragments, progression: fragments.isEmpty ? 0 : nil)
        )
    }

    /// A position at the start of the reading order.
    public var startLocator: Locator? {
        readingOrder.first.flatMap(locator(for:))
    }

    /// The index in ``readingOrder`` of the resource a locator points into.
    public func readingOrderIndex(of locator: Locator) -> Int? {
        let path = Link(href: locator.href).path
        return readingOrder.firstIndex { $0.path == path }
    }

    /// The first table of contents title for a resource, depth first.
    private func title(forPath path: String, in links: [Link]) -> String? {
        for link in links {
            if link.path == path, let title = link.title {
                return title
            }
            if let title = title(forPath: path, in: link.children) {
                return title
            }
        }
        return nil
    }
}
