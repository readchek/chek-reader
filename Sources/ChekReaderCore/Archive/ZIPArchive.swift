import Foundation

/// A ZIP archive read from memory or a memory-mapped file.
///
/// Opening reads only the central directory. Entries are decompressed and
/// checked against their CRC-32 when they're read. Every size, count and
/// offset in the archive is checked against the data and ``ReaderLimits``
/// before it's used.
package struct ZIPArchive: PublicationContainer {
    /// One file in the archive.
    package struct Entry: Hashable, Sendable {
        /// The normalized path, without a leading slash.
        package let path: String
        package let method: UInt16
        package let flags: UInt16
        package let crc32: UInt32
        package let compressedSize: Int64
        package let uncompressedSize: Int64
        package let localHeaderOffset: Int64

        /// Whether the entry uses ZIP's own encryption.
        package var isEncrypted: Bool { flags & 1 != 0 }
    }

    private let bytes: ByteReader
    private let limits: ReaderLimits
    /// The entries by path.
    package let entries: [String: Entry]
    package let paths: Set<String>?

    /// Opens an archive file, memory-mapping it so only the parts read are loaded.
    package init(contentsOf url: URL, limits: ReaderLimits) throws(ReaderError) {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw .malformed(reason: "\(url.lastPathComponent) could not be read. Check that the file exists and the app can access it.")
        }
        try self.init(data: data, limits: limits)
    }

    /// Opens an archive in memory.
    package init(data: Data, limits: ReaderLimits) throws(ReaderError) {
        bytes = ByteReader(data)
        self.limits = limits
        entries = try Self.readCentralDirectory(bytes, limits: limits)
        paths = Set(entries.keys)
    }

    package func data(at path: String) async throws(ReaderError) -> Data {
        try read(path)
    }

    package func length(of path: String) async -> Int64? {
        entries[path]?.uncompressedSize
    }

    /// The decompressed bytes of the entry at `path`.
    package func read(_ path: String) throws(ReaderError) -> Data {
        guard let entry = entries[path] else {
            throw .malformed(reason: "The archive has no entry named \(path).")
        }
        return try read(entry)
    }

    /// The decompressed bytes of `entry`.
    package func read(_ entry: Entry) throws(ReaderError) -> Data {
        if entry.isEncrypted {
            throw .drmProtected(scheme: "ZIP encryption")
        }
        guard entry.uncompressedSize <= limits.maxResourceBytes else {
            throw .limitExceeded(.resourceBytes)
        }
        // Small entries are exempt from the ratio check: a short run of
        // whitespace legitimately compresses hundreds of times over.
        if entry.uncompressedSize > 1 << 20,
           Double(entry.uncompressedSize) > Double(max(entry.compressedSize, 1)) * limits.maxCompressionRatio {
            throw .limitExceeded(.compressionRatio)
        }

        let header = Int(entry.localHeaderOffset)
        guard try bytes.uint32(at: header) == 0x0403_4B50 else {
            throw .malformed(reason: "The local header of \(entry.path) is missing.")
        }
        let nameLength = try Int(bytes.uint16(at: header + 26))
        let extraLength = try Int(bytes.uint16(at: header + 28))
        let stored = try bytes.data(at: header + 30 + nameLength + extraLength, count: Int(entry.compressedSize))

        let content: Data
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else {
                throw .malformed(reason: "The stored entry \(entry.path) has mismatched sizes.")
            }
            content = stored
        case 8:
            content = try Inflate.decompress(stored, expectedSize: Int(entry.uncompressedSize))
        default:
            throw .malformed(reason: "\(entry.path) uses ZIP compression method \(entry.method), which isn't supported. Repack the archive with Deflate.")
        }
        guard CRC32.checksum(content) == entry.crc32 else {
            throw .malformed(reason: "\(entry.path) is corrupted: its checksum doesn't match.")
        }
        return content
    }

    // MARK: - Central directory

    private static let endOfCentralDirectory: UInt32 = 0x0605_4B50
    private static let zip64Locator: UInt32 = 0x0706_4B50
    private static let zip64EndOfCentralDirectory: UInt32 = 0x0606_4B50
    private static let centralFileHeader: UInt32 = 0x0201_4B50

    private static func readCentralDirectory(_ bytes: ByteReader, limits: ReaderLimits) throws(ReaderError) -> [String: Entry] {
        let end = try findEndOfCentralDirectory(bytes)
        var diskNumber = try Int(bytes.uint16(at: end + 4))
        var directoryDisk = try Int(bytes.uint16(at: end + 6))
        var entryCount = try Int64(bytes.uint16(at: end + 10))
        var directorySize = try Int64(bytes.uint32(at: end + 12))
        var directoryOffset = try Int64(bytes.uint32(at: end + 16))

        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = end - 20
            if locator >= 0, try bytes.uint32(at: locator) == zip64Locator {
                let record = try Int(bytes.int64(at: locator + 8))
                guard try bytes.uint32(at: record) == zip64EndOfCentralDirectory else {
                    throw .malformed(reason: "The archive's ZIP64 directory record is missing.")
                }
                diskNumber = try Int(bytes.uint32(at: record + 16))
                directoryDisk = try Int(bytes.uint32(at: record + 20))
                entryCount = try bytes.int64(at: record + 32)
                directorySize = try bytes.int64(at: record + 40)
                directoryOffset = try bytes.int64(at: record + 48)
            }
        }
        guard diskNumber == 0, directoryDisk == 0 else {
            throw .malformed(reason: "The archive is split across several files, which isn't supported.")
        }
        guard entryCount <= Int64(limits.maxArchiveEntries) else {
            throw .limitExceeded(.archiveEntries)
        }
        guard directoryOffset >= 0, directorySize >= 0,
              directoryOffset + directorySize <= Int64(end)
        else {
            throw .malformed(reason: "The archive's central directory is outside the file.")
        }

        var entries: [String: Entry] = [:]
        entries.reserveCapacity(Int(entryCount))
        var totalSize: Int64 = 0
        var position = Int(directoryOffset)
        let directoryEnd = Int(directoryOffset + directorySize)

        for _ in 0..<entryCount {
            guard position + 46 <= directoryEnd, try bytes.uint32(at: position) == centralFileHeader else {
                throw .malformed(reason: "The archive's central directory is damaged.")
            }
            let flags = try bytes.uint16(at: position + 8)
            let method = try bytes.uint16(at: position + 10)
            let crc32 = try bytes.uint32(at: position + 16)
            var compressedSize = try Int64(bytes.uint32(at: position + 20))
            var uncompressedSize = try Int64(bytes.uint32(at: position + 24))
            let nameLength = try Int(bytes.uint16(at: position + 28))
            let extraLength = try Int(bytes.uint16(at: position + 30))
            let commentLength = try Int(bytes.uint16(at: position + 32))
            var localHeaderOffset = try Int64(bytes.uint32(at: position + 42))
            let nameStart = position + 46
            let extraStart = nameStart + nameLength
            position = extraStart + extraLength + commentLength
            guard position <= directoryEnd else {
                throw .malformed(reason: "The archive's central directory is damaged.")
            }

            if uncompressedSize == 0xFFFF_FFFF || compressedSize == 0xFFFF_FFFF || localHeaderOffset == 0xFFFF_FFFF {
                try readZIP64Extra(
                    bytes, from: extraStart, count: extraLength,
                    uncompressedSize: &uncompressedSize,
                    compressedSize: &compressedSize,
                    localHeaderOffset: &localHeaderOffset
                )
            }

            let rawName = try bytes.data(at: nameStart, count: nameLength)
            let name = decodeName(rawName, isUTF8: flags & 0x0800 != 0)
            if name.hasSuffix("/") || name.hasSuffix("\\") {
                continue
            }
            let path = try normalize(name)
            guard entries[path] == nil else {
                throw .malformed(reason: "The archive has two entries named \(path).")
            }
            guard compressedSize >= 0, uncompressedSize >= 0,
                  localHeaderOffset >= 0, localHeaderOffset < directoryOffset
            else {
                throw .malformed(reason: "The archive entry \(path) has an invalid size or offset.")
            }
            totalSize += uncompressedSize
            guard totalSize <= limits.maxUncompressedBytes else {
                throw .limitExceeded(.uncompressedBytes)
            }
            entries[path] = Entry(
                path: path,
                method: method,
                flags: flags,
                crc32: crc32,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            )
        }
        return entries
    }

    /// Finds the end of central directory record, which sits in the last
    /// 22 bytes plus an optional comment of up to 64 KiB.
    private static func findEndOfCentralDirectory(_ bytes: ByteReader) throws(ReaderError) -> Int {
        let recordSize = 22
        guard bytes.count >= recordSize else {
            throw .malformed(reason: "The file is too short to be a ZIP archive.")
        }
        let lowest = max(0, bytes.count - recordSize - 0xFFFF)
        var offset = bytes.count - recordSize
        while offset >= lowest {
            if try bytes.uint32(at: offset) == endOfCentralDirectory,
               try offset + recordSize + Int(bytes.uint16(at: offset + 20)) <= bytes.count {
                return offset
            }
            offset -= 1
        }
        throw .malformed(reason: "The ZIP archive's central directory is missing. The file may be truncated.")
    }

    /// Reads the 64-bit values that replace any 32-bit field set to 0xFFFFFFFF.
    private static func readZIP64Extra(
        _ bytes: ByteReader,
        from start: Int,
        count: Int,
        uncompressedSize: inout Int64,
        compressedSize: inout Int64,
        localHeaderOffset: inout Int64
    ) throws(ReaderError) {
        var position = start
        let end = start + count
        while position + 4 <= end {
            let id = try bytes.uint16(at: position)
            let size = try Int(bytes.uint16(at: position + 2))
            let fieldEnd = position + 4 + size
            guard fieldEnd <= end else { break }
            if id == 0x0001 {
                var field = position + 4
                if uncompressedSize == 0xFFFF_FFFF, field + 8 <= fieldEnd {
                    uncompressedSize = try bytes.int64(at: field)
                    field += 8
                }
                if compressedSize == 0xFFFF_FFFF, field + 8 <= fieldEnd {
                    compressedSize = try bytes.int64(at: field)
                    field += 8
                }
                if localHeaderOffset == 0xFFFF_FFFF, field + 8 <= fieldEnd {
                    localHeaderOffset = try bytes.int64(at: field)
                }
                return
            }
            position = fieldEnd
        }
    }

    private static func decodeName(_ data: Data, isUTF8: Bool) -> String {
        if let name = String(data: data, encoding: .utf8) {
            return name
        }
        // Names without the UTF-8 flag are meant to be code page 437. Latin-1
        // keeps ASCII intact and never fails, which is enough to find entries.
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Normalizes an entry name to a relative path and rejects names that
    /// could resolve outside the archive.
    private static func normalize(_ name: String) throws(ReaderError) -> String {
        let slashed = name.replacingOccurrences(of: "\\", with: "/")
        if slashed.hasPrefix("/") || slashed.dropFirst().hasPrefix(":") {
            throw .malformed(reason: "The archive entry \(name) has an absolute path.")
        }
        var components: [Substring] = []
        for component in slashed.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                throw .malformed(reason: "The archive entry \(name) points outside the archive.")
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else {
            throw .malformed(reason: "The archive has an entry with an empty name.")
        }
        return components.joined(separator: "/")
    }
}

/// Bounds-checked little-endian reads from `Data`, by offset from its start.
private struct ByteReader: Sendable {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    var count: Int { data.count }

    private func check(_ offset: Int, _ length: Int) throws(ReaderError) {
        guard offset >= 0, length >= 0, offset <= data.count - length else {
            throw .malformed(reason: "The archive points past the end of the file. It may be truncated.")
        }
    }

    func uint16(at offset: Int) throws(ReaderError) -> UInt16 {
        try check(offset, 2)
        let base = data.startIndex + offset
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    func uint32(at offset: Int) throws(ReaderError) -> UInt32 {
        try check(offset, 4)
        let base = data.startIndex + offset
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[base + index]) << (8 * index)
        }
        return value
    }

    /// A 64-bit value, rejected when it doesn't fit in `Int64`.
    func int64(at offset: Int) throws(ReaderError) -> Int64 {
        try check(offset, 8)
        let base = data.startIndex + offset
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[base + index]) << (8 * index)
        }
        guard value <= UInt64(Int64.max) else {
            throw .malformed(reason: "The archive records a size that is too large.")
        }
        return Int64(value)
    }

    /// A copy of `count` bytes, starting from 0 so callers can index it directly.
    func data(at offset: Int, count: Int) throws(ReaderError) -> Data {
        try check(offset, count)
        let base = data.startIndex + offset
        return Data(data[base..<base + count])
    }
}
