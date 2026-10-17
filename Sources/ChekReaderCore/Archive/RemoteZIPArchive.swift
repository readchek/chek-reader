import Foundation

/// A ZIP archive on an HTTP server, read with range requests.
///
/// Opening fetches the end of the file, and the central directory if it
/// isn't there, so a book opens after one or two requests whatever its
/// size. Each entry is then fetched on its own when it's read. Servers that
/// don't support ranges get one request for the whole file instead.
package enum RemoteZIPArchive {
    /// Opens the archive at `url`.
    ///
    /// The result reads entries over HTTP, or from memory when the server
    /// sent the whole file.
    package static func open(_ url: URL, options: RemoteOptions, limits: ReaderLimits) async throws(ReaderError) -> any PublicationContainer {
        let opened = try await HTTPByteSource.open(
            url,
            options: options,
            tailLength: ZIPArchive.tailLength,
            maxBytes: limits.maxUncompressedBytes
        )
        switch opened {
        case .whole(let data):
            return try ZIPArchive(data: data, limits: limits)
        case .ranges(let source, let tail):
            return try await RangedZIPArchive(source: source, tail: tail, limits: limits)
        }
    }
}

/// The ranged half of ``RemoteZIPArchive``.
struct RangedZIPArchive: PublicationContainer {
    private let source: HTTPByteSource
    private let limits: ReaderLimits
    private let entries: [String: ZIPArchive.Entry]
    let paths: Set<String>?

    /// The bytes fetched past an entry's stored data with its header, so a
    /// local extra field longer than the directory's rarely needs a second
    /// request.
    private static let headerSlack = 1024

    init(source: HTTPByteSource, tail: Data, limits: ReaderLimits) async throws(ReaderError) {
        self.source = source
        self.limits = limits
        let tailReader = ByteReader(tail, base: Int(source.count) - tail.count)
        let location = try ZIPArchive.locateDirectory(in: tailReader, limits: limits)

        let directory: ByteReader
        if tailReader.contains(Int(location.offset), Int(location.size)) {
            directory = tailReader
        } else {
            // About 100 bytes per entry, so the entry limit bounds the
            // directory without trusting its recorded size.
            guard location.size <= Int64(limits.maxArchiveEntries) * 1024 else {
                throw .limitExceeded(.archiveEntries)
            }
            let data = try await source.read(location.offset..<(location.offset + location.size))
            directory = ByteReader(data, base: Int(location.offset))
        }
        entries = try ZIPArchive.readDirectory(directory, at: location, limits: limits)
        paths = Set(entries.keys)
    }

    func data(at path: String) async throws(ReaderError) -> Data {
        guard let entry = entries[path] else {
            throw .malformed(reason: "The archive has no entry named \(path).")
        }
        try ZIPArchive.checkReadable(entry, limits: limits)

        let header = entry.localHeaderOffset
        // Checked without adding, so a recorded size near Int64.max can't overflow.
        guard header < source.count, entry.compressedSize <= source.count - header else {
            throw .malformed(reason: "\(entry.path) points past the end of the archive. It may be truncated.")
        }
        // The header, the stored data and some slack, in one request.
        let guess = min(source.count - header, Int64(ZIPArchive.localHeaderSize + Self.headerSlack) + entry.compressedSize)
        let first = try await source.read(header..<(header + guess))
        var chunk = ByteReader(first, base: Int(header))
        let start = try ZIPArchive.dataStart(ofEntryAt: Int(header), in: chunk, path: entry.path)
        let length = Int(entry.compressedSize)
        if !chunk.contains(start, length) {
            let rest = try await source.read(Int64(start)..<Int64(start + length))
            chunk = ByteReader(rest, base: start)
        }
        let stored = try chunk.data(at: start, count: length)
        return try ZIPArchive.decode(entry, stored: stored)
    }

    func length(of path: String) async -> Int64? {
        entries[path]?.uncompressedSize
    }
}
