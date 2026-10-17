import ChekReaderCore
import Foundation

/// An embedded font from a KF8 `FONT` record.
///
/// The record is a 24-byte header, then the font: optionally XOR-obfuscated
/// over its first 1040 bytes with a key stored in the record, then
/// optionally zlib-compressed. This follows calibre's `read_font_record`.
struct MOBIFont: Sendable {
    let data: [UInt8]
    let fileExtension: String
    let mediaType: String

    /// Only the start of the font is obfuscated, as with EPUB's font obfuscation.
    private static let obfuscatedLength = 1040

    static func decode(_ record: [UInt8], limits: ReaderLimits) throws(ReaderError) -> MOBIFont {
        let bytes = BigEndianBytes(record, name: "FONT record")
        let decodedSize = Int(try bytes.uint32(at: 4))
        let flags = try bytes.uint32(at: 8)
        let dataStart = Int(try bytes.uint32(at: 12))
        let keyLength = Int(try bytes.uint32(at: 16))
        let keyStart = Int(try bytes.uint32(at: 20))
        guard dataStart >= 24, dataStart <= record.count else {
            throw .malformed(reason: "Its data starts outside the record.")
        }
        var font = Array(record[dataStart...])

        if flags & 0b10 != 0 {
            guard keyLength > 0, bytes.contains(keyStart, keyLength) else {
                throw .malformed(reason: "Its obfuscation key is outside the record.")
            }
            let key = try bytes.bytes(at: keyStart, count: keyLength)
            for index in 0..<min(Self.obfuscatedLength, font.count) {
                font[index] ^= key[index % keyLength]
            }
        }

        if flags & 0b1 != 0 {
            guard Int64(decodedSize) <= limits.maxResourceBytes else {
                throw .limitExceeded(.resourceBytes)
            }
            guard Double(decodedSize) <= Double(max(font.count, 1)) * limits.maxCompressionRatio else {
                throw .limitExceeded(.compressionRatio)
            }
            font = [UInt8](try Inflate.decompress(Data(Self.stripZlibHeader(font)), expectedSize: decodedSize))
        }

        let signature = Array(font.prefix(4))
        if signature == [0x00, 0x01, 0x00, 0x00] || signature.hasSignature("true") || signature.hasSignature("ttcf") {
            return MOBIFont(data: font, fileExtension: "ttf", mediaType: "font/ttf")
        }
        if signature.hasSignature("OTTO") {
            return MOBIFont(data: font, fileExtension: "otf", mediaType: "font/otf")
        }
        if signature.hasSignature("wOFF") {
            return MOBIFont(data: font, fileExtension: "woff", mediaType: "font/woff")
        }
        if signature.hasSignature("wOF2") {
            return MOBIFont(data: font, fileExtension: "woff2", mediaType: "font/woff2")
        }
        throw .malformed(reason: "It isn't a TrueType, OpenType or WOFF font.")
    }

    /// The raw DEFLATE data inside zlib framing. ``Inflate`` reads raw
    /// DEFLATE, so the two-byte zlib header goes; the checksum after the
    /// last block is never read.
    static func stripZlibHeader(_ bytes: [UInt8]) -> [UInt8] {
        guard bytes.count >= 2 else { return bytes }
        let header = Int(bytes[0]) << 8 | Int(bytes[1])
        let isZlib = bytes[0] & 0x0F == 8 && header % 31 == 0
        return isZlib ? Array(bytes[2...]) : bytes
    }
}
