import ChekReaderCore
import Foundation

/// A TAR archive in memory or a memory-mapped file, as CBT comics use.
///
/// Opening walks the headers once; entries are read on demand. POSIX
/// ustar, GNU long names and pax `path` records are understood. Every size
/// and offset is checked against the data and ``ReaderLimits`` before it's
/// used.
struct TARArchive: PublicationContainer {
    private struct Entry: Sendable {
        let offset: Int
        let size: Int
    }

    private let data: Data
    private let entries: [String: Entry]
    let paths: Set<String>?

    private static let blockSize = 512

    init(data: Data, limits: ReaderLimits) throws(ReaderError) {
        self.data = data
        var entries: [String: Entry] = [:]
        var offset = 0
        var total: Int64 = 0
        // A name from a GNU long name entry or a pax header, for the entry that follows.
        var pendingName: String?

        while offset + Self.blockSize <= data.count {
            try ReaderError.checkCancellation()
            let header = data.subdata(in: data.startIndex + offset..<data.startIndex + offset + Self.blockSize)
            if header.allSatisfy({ $0 == 0 }) {
                break
            }
            guard Self.checksumMatches(header) else {
                throw .malformed(reason: "A TAR header at byte \(offset) is damaged. The archive may be truncated or not a TAR file.")
            }
            guard let size = Self.octal(header, at: 124, length: 12), size >= 0 else {
                throw .malformed(reason: "A TAR header at byte \(offset) has an unreadable size.")
            }
            let start = offset + Self.blockSize
            // Checked without adding, so a huge recorded size can't overflow.
            guard size <= data.count - start else {
                throw .malformed(reason: "A TAR entry at byte \(offset) runs past the end of the archive. It may be truncated.")
            }
            let type = header[header.startIndex + 156]
            let padded = (size + Self.blockSize - 1) / Self.blockSize * Self.blockSize

            switch type {
            case UInt8(ascii: "L"):
                // GNU long name: the entry's data is the next entry's name.
                pendingName = Self.string(data.subdata(in: data.startIndex + start..<data.startIndex + start + min(size, 4096)))
            case UInt8(ascii: "x"):
                let records = data.subdata(in: data.startIndex + start..<data.startIndex + start + min(size, 1 << 16))
                pendingName = Self.paxPath(records) ?? pendingName
            case 0, UInt8(ascii: "0"), UInt8(ascii: "7"):
                let name = pendingName ?? Self.headerName(header)
                pendingName = nil
                guard Int64(size) <= limits.maxResourceBytes else {
                    throw .limitExceeded(.resourceBytes)
                }
                total += Int64(size)
                guard total <= limits.maxUncompressedBytes else {
                    throw .limitExceeded(.uncompressedBytes)
                }
                if let path = Self.normalize(name) {
                    entries[path] = Entry(offset: start, size: size)
                    guard entries.count <= limits.maxArchiveEntries else {
                        throw .limitExceeded(.archiveEntries)
                    }
                }
            default:
                // Directories, links and other special entries carry no pages.
                pendingName = nil
            }
            guard padded <= data.count - start else { break }
            offset = start + padded
        }
        self.entries = entries
        paths = Set(entries.keys)
    }

    func data(at path: String) async throws(ReaderError) -> Data {
        guard let entry = entries[path] else {
            throw .malformed(reason: "The archive has no entry named \(path).")
        }
        return data.subdata(in: data.startIndex + entry.offset..<data.startIndex + entry.offset + entry.size)
    }

    func length(of path: String) async -> Int64? {
        entries[path].map { Int64($0.size) }
    }

    // MARK: - Headers

    /// Whether the header's checksum, the sum of its bytes with the
    /// checksum field read as spaces, matches the one recorded.
    private static func checksumMatches(_ header: Data) -> Bool {
        guard let recorded = octal(header, at: 148, length: 8) else { return false }
        var sum = 0
        for (index, byte) in header.enumerated() {
            sum += (148..<156).contains(index) ? 32 : Int(byte)
        }
        return sum == recorded
    }

    /// An octal number field, which may be padded with spaces or NULs.
    private static func octal(_ header: Data, at offset: Int, length: Int) -> Int? {
        let field = header[(header.startIndex + offset)..<(header.startIndex + offset + length)]
        if let first = field.first, first & 0x80 != 0 {
            // GNU base-256 for sizes of 8 GiB and more, beyond any limit.
            return nil
        }
        var value = 0
        var sawDigit = false
        for byte in field {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                guard value < Int.max / 8 else { return nil }
                value = value * 8 + Int(byte - UInt8(ascii: "0"))
                sawDigit = true
            case 0, UInt8(ascii: " "):
                if sawDigit { return value }
            default:
                return nil
            }
        }
        return sawDigit ? value : 0
    }

    private static func headerName(_ header: Data) -> String {
        let name = string(header.subdata(in: header.startIndex..<header.startIndex + 100))
        let isUSTAR = header.subdata(in: header.startIndex + 257..<header.startIndex + 262) == Data("ustar".utf8)
        let prefix = isUSTAR ? string(header.subdata(in: header.startIndex + 345..<header.startIndex + 500)) : ""
        return prefix.isEmpty ? name : prefix + "/" + name
    }

    /// A NUL-terminated field as UTF-8, falling back to Latin-1 for old archives.
    private static func string(_ field: Data) -> String {
        let bytes = field.prefix { $0 != 0 }
        return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }

    /// The `path` from pax extended header records, `"<length> path=<value>\n"`.
    private static func paxPath(_ records: Data) -> String? {
        let text = String(decoding: records, as: UTF8.self)
        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let record = line[line.index(after: space)...]
            if record.hasPrefix("path=") {
                return String(record.dropFirst(5))
            }
        }
        return nil
    }

    /// The path without a leading `./` or `/`, or `nil` for one that climbs
    /// out of the archive.
    private static func normalize(_ name: String) -> String? {
        let components = name.split(separator: "/").filter { $0 != "." }
        guard !components.isEmpty, !components.contains("..") else { return nil }
        return components.joined(separator: "/")
    }
}
