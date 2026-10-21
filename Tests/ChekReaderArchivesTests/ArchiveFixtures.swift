import ChekReaderCore
import Foundation
#if canImport(ArchiveKit)
import ArchiveKit
#else
import CLibArchive
#endif

/// Builds RAR archives by hand: RAR 4 with every file stored, which is
/// enough for the reader to open, since no free tool writes RAR.
enum RARFixture {
    static func archive(_ entries: [(name: String, content: Data)]) -> Data {
        var out = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])
        out += block(type: 0x73, flags: 0, body: Data(count: 6))
        for (name, content) in entries {
            var body = Data()
            body += le32(UInt32(content.count)) // packed size
            body += le32(UInt32(content.count)) // unpacked size
            body.append(3) // host OS: Unix
            body += le32(CRC32.checksum(content))
            body += le32(0) // DOS time
            body.append(20) // version needed to extract: 2.0
            body.append(0x30) // method: store
            body += le16(UInt16(name.utf8.count))
            body += le32(0o100644) // attributes
            body += Data(name.utf8)
            out += block(type: 0x74, flags: 0x8000, body: body)
            out += content
        }
        out += block(type: 0x7B, flags: 0x4000, body: Data())
        return out
    }

    /// A header block: its CRC-16 (the low half of a CRC-32 over the
    /// rest), type, flags, size and `body`.
    private static func block(type: UInt8, flags: UInt16, body: Data) -> Data {
        let header = Data([type]) + le16(flags) + le16(UInt16(7 + body.count)) + body
        return le16(UInt16(CRC32.checksum(header) & 0xFFFF)) + header
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data((0..<4).map { UInt8((value >> (8 * $0)) & 0xFF) })
    }
}

/// Builds 7-Zip archives with libarchive's writer.
enum SevenZipFixture {
    static func archive(_ entries: [(name: String, content: Data)]) -> Data {
        guard let archive = unsafe archive_write_new() else { return Data() }
        defer { _ = unsafe archive_write_free(archive) }
        unsafe archive_write_set_format_7zip(archive)
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        var used = 0
        unsafe buffer.withUnsafeMutableBytes { bytes in
            _ = unsafe archive_write_open_memory(archive, bytes.baseAddress, bytes.count, &used)
            for (name, content) in entries {
                guard let entry = unsafe archive_entry_new() else { continue }
                unsafe archive_entry_set_pathname(entry, name)
                unsafe archive_entry_set_size(entry, Int64(content.count))
                unsafe archive_entry_set_filetype(entry, 0o100000)
                unsafe archive_entry_set_perm(entry, 0o644)
                _ = unsafe archive_write_header(archive, entry)
                _ = unsafe content.withUnsafeBytes { unsafe archive_write_data(archive, $0.baseAddress, $0.count) }
                unsafe archive_entry_free(entry)
            }
            _ = unsafe archive_write_close(archive)
        }
        return Data(buffer[..<used])
    }
}
