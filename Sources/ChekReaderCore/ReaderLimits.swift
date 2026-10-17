/// Upper bounds applied to every publication, local or remote.
///
/// Exceeding a limit fails with ``ReaderError/limitExceeded(_:)`` instead of
/// exhausting memory or disk. The defaults are generous for real books and
/// tight enough to stop malformed or hostile files.
public struct ReaderLimits: Hashable, Sendable {
    /// The most entries an archive may list.
    public var maxArchiveEntries: Int
    /// The most bytes all entries may expand to, combined.
    public var maxUncompressedBytes: Int64
    /// The most bytes a single resource may expand to.
    public var maxResourceBytes: Int64
    /// The highest ratio of expanded to compressed size for one entry.
    public var maxCompressionRatio: Double
    /// The deepest an XML document may nest.
    public var maxXMLDepth: Int

    public init(
        maxArchiveEntries: Int = 20_000,
        maxUncompressedBytes: Int64 = 4 << 30,
        maxResourceBytes: Int64 = 512 << 20,
        maxCompressionRatio: Double = 200,
        maxXMLDepth: Int = 256
    ) {
        self.maxArchiveEntries = maxArchiveEntries
        self.maxUncompressedBytes = maxUncompressedBytes
        self.maxResourceBytes = maxResourceBytes
        self.maxCompressionRatio = maxCompressionRatio
        self.maxXMLDepth = maxXMLDepth
    }

    public static let `default` = ReaderLimits()

    /// Which limit was exceeded.
    public enum Limit: String, Hashable, Sendable {
        case archiveEntries
        case uncompressedBytes
        case resourceBytes
        case compressionRatio
        case xmlDepth
    }
}
