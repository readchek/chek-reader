import ChekReaderCore

/// PalmDOC compression, the LZ77 variant most MOBI books use for text.
///
/// Each byte of input is one of:
/// - `0x00` and `0x09...0x7F`: itself.
/// - `0x01...0x08`: a count of literal bytes that follow.
/// - `0x80...0xBF`: with the next byte, a back reference: 11 bits of
///   distance and 3 bits of length minus 3.
/// - `0xC0...0xFF`: a space followed by the byte XOR `0x80`.
enum PalmDOC {
    /// Decompresses one record.
    ///
    /// - Parameter limit: The most bytes the output may grow to. Exceeding
    ///   it fails with ``ReaderError/limitExceeded(_:)``.
    static func decompress(_ input: [UInt8], limit: Int) throws(ReaderError) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(min(limit, input.count * 2))
        var position = 0
        func append(_ byte: UInt8) throws(ReaderError) {
            guard output.count < limit else { throw .limitExceeded(.uncompressedBytes) }
            output.append(byte)
        }
        while position < input.count {
            let byte = input[position]
            position += 1
            switch byte {
            case 0x01...0x08:
                let count = Int(byte)
                guard position + count <= input.count else {
                    throw .malformed(reason: "A PalmDOC-compressed text record ends in the middle of a literal run.")
                }
                for index in position..<position + count {
                    try append(input[index])
                }
                position += count
            case 0x80...0xBF:
                guard position < input.count else {
                    throw .malformed(reason: "A PalmDOC-compressed text record ends in the middle of a back reference.")
                }
                let pair = (Int(byte) << 8 | Int(input[position])) & 0x3FFF
                position += 1
                let distance = pair >> 3
                let length = (pair & 0x7) + 3
                guard distance > 0, distance <= output.count else {
                    throw .malformed(reason: "A PalmDOC-compressed text record refers back past its start.")
                }
                // Byte by byte, because a reference may overlap the bytes it produces.
                for _ in 0..<length {
                    try append(output[output.count - distance])
                }
            case 0xC0...0xFF:
                try append(0x20)
                try append(byte ^ 0x80)
            default:
                try append(byte)
            }
        }
        return output
    }
}
