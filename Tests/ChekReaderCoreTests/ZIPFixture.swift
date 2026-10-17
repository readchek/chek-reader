import ChekReaderCore
import Foundation

/// Builds ZIP archives in tests, so no binary fixtures are committed.
struct ZIPFixture {
    struct Entry {
        var name: String
        var content: Data
        /// Raw DEFLATE bytes for `content`. The entry is stored when this is `nil`.
        var deflated: Data?
        var flags: UInt16 = 0x0800
        /// Overrides the recorded checksum, to simulate corruption.
        var crc32: UInt32?
        /// Overrides the recorded uncompressed size, to simulate a lying header.
        var uncompressedSize: UInt32?
    }

    var entries: [Entry] = []

    mutating func add(_ name: String, _ content: String) {
        entries.append(Entry(name: name, content: Data(content.utf8)))
    }

    mutating func add(_ entry: Entry) {
        entries.append(entry)
    }

    func data() -> Data {
        var archive = Data()
        var directory = Data()
        for entry in entries {
            let stored = entry.deflated ?? entry.content
            let method: UInt16 = entry.deflated == nil ? 0 : 8
            let crc = entry.crc32 ?? CRC32.checksum(entry.content)
            let size = entry.uncompressedSize ?? UInt32(entry.content.count)
            let name = Data(entry.name.utf8)
            let offset = UInt32(archive.count)

            archive.append(le32: 0x0403_4B50)
            archive.append(le16: 20)
            archive.append(le16: entry.flags)
            archive.append(le16: method)
            archive.append(le32: 0)                      // time and date
            archive.append(le32: crc)
            archive.append(le32: UInt32(stored.count))
            archive.append(le32: size)
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)                      // extra length
            archive.append(name)
            archive.append(stored)

            directory.append(le32: 0x0201_4B50)
            directory.append(le16: 20)                   // version made by
            directory.append(le16: 20)                   // version needed
            directory.append(le16: entry.flags)
            directory.append(le16: method)
            directory.append(le32: 0)                    // time and date
            directory.append(le32: crc)
            directory.append(le32: UInt32(stored.count))
            directory.append(le32: size)
            directory.append(le16: UInt16(name.count))
            directory.append(le16: 0)                    // extra length
            directory.append(le16: 0)                    // comment length
            directory.append(le16: 0)                    // disk
            directory.append(le16: 0)                    // internal attributes
            directory.append(le32: 0)                    // external attributes
            directory.append(le32: offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32: 0x0605_4B50)
        archive.append(le16: 0)
        archive.append(le16: 0)
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(directory.count))
        archive.append(le32: directoryOffset)
        archive.append(le16: 0)                          // comment length
        return archive
    }
}

extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append(le32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8(value >> (8 * $0) & 0xFF) })
    }
}
