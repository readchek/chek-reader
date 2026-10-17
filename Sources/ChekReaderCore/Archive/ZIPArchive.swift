import Foundation

/// A ZIP archive read from memory or a memory-mapped file.
///
/// ``RemoteZIPArchive`` reads the same format over HTTP ranges, sharing the
/// parsing here. Opening reads only the central directory. Entries are decompressed and
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
        let location = try Self.locateDirectory(in: bytes, limits: limits)
        entries = try Self.readDirectory(bytes, at: location, limits: limits)
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
        try Self.checkReadable(entry, limits: limits)
        let header = Int(entry.localHeaderOffset)
        let start = try Self.dataStart(ofEntryAt: header, in: bytes, path: entry.path)
        let stored = try bytes.data(at: start, count: Int(entry.compressedSize))
        return try Self.decode(entry, stored: stored)
    }

    // MARK: - Entries

    /// Rejects entries that can't or mustn't be read, before any of their
    /// data is read.
    static func checkReadable(_ entry: Entry, limits: ReaderLimits) throws(ReaderError) {
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
    }

    /// The size of a local file header before its variable-length fields.
    static let localHeaderSize = 30

    /// Where an entry's stored data starts, read from its local header,
    /// whose name and extra fields can differ in length from the directory's.
    static func dataStart(ofEntryAt header: Int, in bytes: ByteReader, path: String) throws(ReaderError) -> Int {
        guard try bytes.uint32(at: header) == 0x0403_4B50 else {
            throw .malformed(reason: "The local header of \(path) is missing.")
        }
        let nameLength = try Int(bytes.uint16(at: header + 26))
        let extraLength = try Int(bytes.uint16(at: header + 28))
        return header + localHeaderSize + nameLength + extraLength
    }

    /// Decompresses an entry's stored bytes and checks them against its CRC-32.
    static func decode(_ entry: Entry, stored: Data) throws(ReaderError) -> Data {
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

    /// Where the central directory is and how many entries it holds.
    struct DirectoryLocation: Sendable {
        var offset: Int64
        var size: Int64
        var count: Int64
    }

    /// The bytes from the end of central directory record's earliest
    /// possible start to the end of the file, including room for a ZIP64
    /// locator and record before it.
    static let tailLength: Int64 = 22 + 0xFFFF + 20 + 56

    /// Finds the central directory from the end of the archive. `bytes`
    /// must reach the end of the file, but may start anywhere.
    static func locateDirectory(in bytes: ByteReader, limits: ReaderLimits) throws(ReaderError) -> DirectoryLocation {
        let end = try findEndOfCentralDirectory(bytes)
        var diskNumber = try Int(bytes.uint16(at: end + 4))
        var directoryDisk = try Int(bytes.uint16(at: end + 6))
        var entryCount = try Int64(bytes.uint16(at: end + 10))
        var directorySize = try Int64(bytes.uint32(at: end + 12))
        var directoryOffset = try Int64(bytes.uint32(at: end + 16))

        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let locator = end - 20
            if bytes.contains(locator, 4), try bytes.uint32(at: locator) == zip64Locator {
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
        // Compared without adding, so sizes near Int64.max can't overflow.
        guard directoryOffset >= 0, directorySize >= 0,
              directoryOffset <= Int64(end), directorySize <= Int64(end) - directoryOffset
        else {
            throw .malformed(reason: "The archive's central directory is outside the file.")
        }
        return DirectoryLocation(offset: directoryOffset, size: directorySize, count: entryCount)
    }

    /// Reads every entry in the central directory. `bytes` must hold the
    /// whole directory.
    static func readDirectory(_ bytes: ByteReader, at location: DirectoryLocation, limits: ReaderLimits) throws(ReaderError) -> [String: Entry] {
        let directoryOffset = location.offset
        let entryCount = location.count
        var entries: [String: Entry] = [:]
        entries.reserveCapacity(Int(entryCount))
        var totalSize: Int64 = 0
        var position = Int(directoryOffset)
        let directoryEnd = Int(directoryOffset + location.size)

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
        let fileEnd = bytes.base + bytes.count
        let lowest = max(bytes.base, fileEnd - recordSize - 0xFFFF)
        var offset = fileEnd - recordSize
        while offset >= lowest {
            if try bytes.uint32(at: offset) == endOfCentralDirectory,
               try offset + recordSize + Int(bytes.uint16(at: offset + 20)) <= fileEnd {
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

/// Bounds-checked little-endian reads from part of an archive, by offset
/// from the start of the archive.
struct ByteReader: Sendable {
    let data: Data
    /// The archive offset of the first byte of `data`.
    let base: Int

    init(_ data: Data, base: Int = 0) {
        self.data = data
        self.base = base
    }

    var count: Int { data.count }

    /// Whether `offset..<offset + length` is within the bytes held.
    func contains(_ offset: Int, _ length: Int) -> Bool {
        offset >= base && length >= 0 && offset - base <= data.count - length
    }

    /// Checks the range and returns where it starts within `data`.
    private func check(_ offset: Int, _ length: Int) throws(ReaderError) -> Int {
        guard contains(offset, length) else {
            throw .malformed(reason: "The archive points past the end of the file. It may be truncated.")
        }
        return data.startIndex + offset - base
    }

    func uint16(at offset: Int) throws(ReaderError) -> UInt16 {
        let base = try check(offset, 2)
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    func uint32(at offset: Int) throws(ReaderError) -> UInt32 {
        let base = try check(offset, 4)
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(data[base + index]) << (8 * index)
        }
        return value
    }

    /// A 64-bit value, rejected when it doesn't fit in `Int64`.
    func int64(at offset: Int) throws(ReaderError) -> Int64 {
        let base = try check(offset, 8)
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
        let base = try check(offset, count)
        return Data(data[base..<base + count])
    }
}
