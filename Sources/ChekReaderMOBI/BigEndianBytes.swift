import ChekReaderCore

/// Bounds-checked big-endian reads from one record's bytes.
///
/// Every value in a Palm database is big-endian, and every offset comes
/// from the file, so each read checks its range and fails with
/// ``ReaderError/malformed(reason:)`` instead of trapping.
struct BigEndianBytes: Sendable {
    let bytes: [UInt8]
    /// What the bytes are, for error messages, such as "record 0".
    let name: String

    init(_ bytes: [UInt8], name: String) {
        self.bytes = bytes
        self.name = name
    }

    var count: Int { bytes.count }

    /// Whether `offset..<offset + length` is within the bytes.
    func contains(_ offset: Int, _ length: Int) -> Bool {
        offset >= 0 && length >= 0 && offset <= bytes.count - length
    }

    private func check(_ offset: Int, _ length: Int) throws(ReaderError) {
        guard contains(offset, length) else {
            throw .malformed(reason: "The MOBI file's \(name) is shorter than its headers say. The file may be truncated.")
        }
    }

    func uint8(at offset: Int) throws(ReaderError) -> UInt8 {
        try check(offset, 1)
        return bytes[offset]
    }

    func uint16(at offset: Int) throws(ReaderError) -> UInt16 {
        try check(offset, 2)
        return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    func uint32(at offset: Int) throws(ReaderError) -> UInt32 {
        try check(offset, 4)
        return Self.uint32(bytes, at: offset)
    }

    /// The value at `offset`, or `nil` when the bytes end before it. Newer
    /// MOBI header fields are only present in longer headers.
    func optionalUInt32(at offset: Int) -> UInt32? {
        guard contains(offset, 4) else { return nil }
        return Self.uint32(bytes, at: offset)
    }

    /// A copy of `count` bytes from `offset`.
    func bytes(at offset: Int, count: Int) throws(ReaderError) -> [UInt8] {
        try check(offset, count)
        return Array(bytes[offset..<offset + count])
    }

    /// Whether the bytes at `offset` are the ASCII `signature`, such as `MOBI`.
    func has(_ signature: String, at offset: Int) -> Bool {
        let expected = Array(signature.utf8)
        guard contains(offset, expected.count) else { return false }
        return bytes[offset..<offset + expected.count].elementsEqual(expected)
    }

    /// Callers have checked that four bytes are available.
    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value = value << 8 | UInt32(bytes[offset + index])
        }
        return value
    }
}

extension Array where Element == UInt8 {
    /// Whether the array starts with the ASCII `signature`.
    func hasSignature(_ signature: String) -> Bool {
        starts(with: signature.utf8)
    }
}
