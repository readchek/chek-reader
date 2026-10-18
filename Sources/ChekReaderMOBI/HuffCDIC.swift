import ChekReaderCore

/// HUFF/CDIC compression: Huffman codes that index a phrase dictionary,
/// where phrases may themselves be compressed. Follows KindleUnpack's
/// `HuffcdicReader`.
///
/// A hostile dictionary can make a phrase refer to itself, directly or
/// through others, or nest phrases to expand without bound. Phrases are
/// expanded once and remembered, a phrase met again while it's being
/// expanded is rejected, nesting is capped, and every expansion counts
/// against the caller's output limit.
struct HuffCDIC {
    private struct CodeInfo {
        let length: Int
        let isTerminal: Bool
        let maxCode: UInt64
    }

    private enum Phrase {
        case compressed([UInt8])
        case expanding
        case expanded([UInt8])
    }

    /// Phrases deeper than this are treated as damage; real dictionaries
    /// nest a few levels at most.
    private static let maxDepth = 32

    private let table1: [CodeInfo]
    private let minCodes: [UInt64]
    private let maxCodes: [UInt64]
    private var dictionary: [Phrase] = []

    /// - Parameters:
    ///   - huff: The HUFF record.
    ///   - cdics: The CDIC records that follow it, in order.
    init(huff: [UInt8], cdics: [[UInt8]]) throws(ReaderError) {
        let bytes = BigEndianBytes(huff, name: "HUFF record")
        guard bytes.has("HUFF", at: 0), try bytes.uint32(at: 4) == 0x18 else {
            throw .malformed(reason: "The MOBI file's HUFF record has an unknown header.")
        }
        let offset1 = Int(try bytes.uint32(at: 8))
        let offset2 = Int(try bytes.uint32(at: 12))

        var table1: [CodeInfo] = []
        table1.reserveCapacity(256)
        for index in 0..<256 {
            let value = try bytes.uint32(at: offset1 + index * 4)
            let length = Int(value & 0x1F)
            let isTerminal = value & 0x80 != 0
            guard length != 0, length > 8 || isTerminal else {
                throw .malformed(reason: "The MOBI file's HUFF table is damaged.")
            }
            let maxCode = ((UInt64(value >> 8) + 1) << UInt64(32 - length)) &- 1
            table1.append(CodeInfo(length: length, isTerminal: isTerminal, maxCode: maxCode))
        }
        self.table1 = table1

        // Index 0 is unused so the arrays index by code length, 1...32.
        var minCodes: [UInt64] = [0]
        var maxCodes: [UInt64] = [0]
        for length in 1...32 {
            let minCode = UInt64(try bytes.uint32(at: offset2 + (length - 1) * 8))
            let maxCode = UInt64(try bytes.uint32(at: offset2 + (length - 1) * 8 + 4))
            minCodes.append(minCode << UInt64(32 - length))
            maxCodes.append(((maxCode + 1) << UInt64(32 - length)) &- 1)
        }
        self.minCodes = minCodes
        self.maxCodes = maxCodes

        for (number, cdic) in cdics.enumerated() {
            let bytes = BigEndianBytes(cdic, name: "CDIC record \(number)")
            guard bytes.has("CDIC", at: 0), try bytes.uint32(at: 4) == 0x10 else {
                throw .malformed(reason: "The MOBI file's CDIC record \(number) has an unknown header.")
            }
            let phraseCount = Int(try bytes.uint32(at: 8))
            let bits = Int(try bytes.uint32(at: 12))
            guard bits <= 16 else {
                throw .malformed(reason: "The MOBI file's CDIC record \(number) is damaged.")
            }
            let count = min(1 << bits, phraseCount - dictionary.count)
            guard count >= 0 else { break }
            for index in 0..<count {
                let phraseOffset = Int(try bytes.uint16(at: 16 + index * 2))
                let header = Int(try bytes.uint16(at: 16 + phraseOffset))
                let phrase = try bytes.bytes(at: 18 + phraseOffset, count: header & 0x7FFF)
                dictionary.append(header & 0x8000 != 0 ? .expanded(phrase) : .compressed(phrase))
            }
        }
    }

    /// Decompresses one text record.
    ///
    /// - Parameter limit: The most bytes the output may grow to. Exceeding
    ///   it fails with ``ReaderError/limitExceeded(_:)``.
    mutating func decompress(_ input: [UInt8], limit: Int) throws(ReaderError) -> [UInt8] {
        try unpack(input, limit: limit, depth: 0)
    }

    private mutating func unpack(_ input: [UInt8], limit: Int, depth: Int) throws(ReaderError) -> [UInt8] {
        guard depth < Self.maxDepth else {
            throw .malformed(reason: "The MOBI file's CDIC dictionary nests too deeply.")
        }
        var output: [UInt8] = []
        var bitsLeft = input.count * 8
        var position = 0
        var buffer = Self.uint64(input, at: 0)
        var shift = 32
        while true {
            if shift <= 0 {
                position += 4
                buffer = Self.uint64(input, at: position)
                shift += 32
            }
            let code = (buffer >> UInt64(shift)) & 0xFFFF_FFFF
            let info = table1[Int(code >> 24)]
            var length = info.length
            var maxCode = info.maxCode
            if !info.isTerminal {
                while length < 32, code < minCodes[length] {
                    length += 1
                }
                maxCode = maxCodes[length]
            }
            shift -= length
            bitsLeft -= length
            if bitsLeft < 0 {
                break
            }
            guard maxCode >= code else {
                throw .malformed(reason: "The MOBI file's HUFF-compressed text is damaged.")
            }
            let index = (maxCode - code) >> UInt64(32 - length)
            guard index < UInt64(dictionary.count) else {
                throw .malformed(reason: "The MOBI file's HUFF-compressed text refers to a phrase that doesn't exist.")
            }
            let phrase: [UInt8]
            switch dictionary[Int(index)] {
            case .expanded(let bytes):
                phrase = bytes
            case .expanding:
                throw .malformed(reason: "The MOBI file's CDIC dictionary has a phrase that contains itself.")
            case .compressed(let bytes):
                dictionary[Int(index)] = .expanding
                phrase = try unpack(bytes, limit: limit - output.count, depth: depth + 1)
                dictionary[Int(index)] = .expanded(phrase)
            }
            guard phrase.count <= limit - output.count else {
                throw .limitExceeded(.uncompressedBytes)
            }
            output += phrase
        }
        return output
    }

    /// Eight bytes from `offset` as a big-endian integer, with zeros past
    /// the end, as KindleUnpack pads the input.
    private static func uint64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in offset..<offset + 8 {
            value = value << 8 | (index >= 0 && index < bytes.count ? UInt64(bytes[index]) : 0)
        }
        return value
    }
}
