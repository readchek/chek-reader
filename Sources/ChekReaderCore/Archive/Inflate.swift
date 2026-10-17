import Foundation
#if canImport(Compression)
import Compression
#endif

/// Decompresses raw DEFLATE data (RFC 1951), the method ZIP uses.
///
/// Apple platforms use the Compression framework. Other platforms, such as
/// the Linux CI job, use a Swift implementation, which is also tested on
/// every platform.
package enum Inflate {
    /// Decompresses `input`, which must expand to exactly `expectedSize` bytes.
    ///
    /// The output is never allowed to grow past `expectedSize`, so a size
    /// recorded in a hostile archive can't be used to exhaust memory.
    package static func decompress(_ input: Data, expectedSize: Int) throws(ReaderError) -> Data {
        guard expectedSize > 0 else {
            return Data()
        }
        #if canImport(Compression)
        return try systemDecompress(input, expectedSize: expectedSize)
        #else
        return try swiftDecompress(input, expectedSize: expectedSize)
        #endif
    }

    /// Decompresses with the Swift implementation, on any platform.
    package static func swiftDecompress(_ input: Data, expectedSize: Int) throws(ReaderError) -> Data {
        var inflater = Inflater(input: [UInt8](input), limit: expectedSize)
        try inflater.run()
        guard inflater.output.count == expectedSize else {
            throw .malformed(reason: "A compressed entry is shorter than its recorded size.")
        }
        return Data(inflater.output)
    }

    #if canImport(Compression)
    private static func systemDecompress(_ input: Data, expectedSize: Int) throws(ReaderError) -> Data {
        guard !input.isEmpty else {
            throw .malformed(reason: "A compressed entry is empty.")
        }
        // One spare byte shows whether the data expands past its recorded size,
        // because compression_decode_buffer stops silently when the buffer fills.
        var output = Data(count: expectedSize + 1)
        // Safe: both buffers are non-empty and stay alive for the duration of
        // their closures, and compression_decode_buffer writes at most
        // `destination.count` bytes and reads at most `source.count` bytes.
        let written = unsafe output.withUnsafeMutableBytes { destination in
            unsafe input.withUnsafeBytes { source in
                unsafe compression_decode_buffer(
                    destination.baseAddress!.assumingMemoryBound(to: UInt8.self), destination.count,
                    source.baseAddress!.assumingMemoryBound(to: UInt8.self), source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else {
            throw .malformed(reason: written > expectedSize
                ? "A compressed entry expands past its recorded size."
                : "A compressed entry is damaged or shorter than its recorded size.")
        }
        output.removeLast()
        return output
    }
    #endif
}

/// A DEFLATE decoder after Mark Adler's puff.c: canonical Huffman codes
/// decoded a bit at a time. It favors being easy to check over speed.
private struct Inflater {
    private let input: [UInt8]
    private var position = 0
    private var bitBuffer = 0
    private var bitCount = 0
    private let limit: Int
    private(set) var output: [UInt8] = []

    init(input: [UInt8], limit: Int) {
        self.input = input
        self.limit = limit
        output.reserveCapacity(limit)
    }

    mutating func run() throws(ReaderError) {
        var isLast = false
        while !isLast {
            isLast = try bits(1) == 1
            switch try bits(2) {
            case 0: try stored()
            case 1: try codes(Huffman.fixedLengths, Huffman.fixedDistances)
            case 2: try dynamic()
            default: throw Self.damaged
            }
        }
    }

    private static let damaged = ReaderError.malformed(reason: "A compressed entry is damaged.")
    private static let tooLong = ReaderError.malformed(reason: "A compressed entry expands past its recorded size.")

    private mutating func bits(_ count: Int) throws(ReaderError) -> Int {
        var value = bitBuffer
        while bitCount < count {
            guard position < input.count else {
                throw .malformed(reason: "A compressed entry ends early.")
            }
            value |= Int(input[position]) << bitCount
            position += 1
            bitCount += 8
        }
        bitBuffer = value >> count
        bitCount -= count
        return value & ((1 << count) - 1)
    }

    private mutating func stored() throws(ReaderError) {
        // `bits` never buffers a whole byte, so dropping the buffer moves to
        // the next byte boundary.
        bitBuffer = 0
        bitCount = 0
        guard position + 4 <= input.count else { throw Self.damaged }
        let length = Int(input[position]) | Int(input[position + 1]) << 8
        let complement = Int(input[position + 2]) | Int(input[position + 3]) << 8
        position += 4
        guard length == ~complement & 0xFFFF, position + length <= input.count else { throw Self.damaged }
        guard output.count + length <= limit else { throw Self.tooLong }
        output.append(contentsOf: input[position..<position + length])
        position += length
    }

    private mutating func decode(_ code: Huffman) throws(ReaderError) -> Int {
        var value = 0
        var first = 0
        var index = 0
        for length in 1...Huffman.maxBits {
            value |= try bits(1)
            let count = code.counts[length]
            if value - count < first {
                return code.symbols[index + value - first]
            }
            index += count
            first = (first + count) << 1
            value <<= 1
        }
        throw Self.damaged
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private mutating func codes(_ lengthCode: Huffman, _ distanceCode: Huffman) throws(ReaderError) {
        while true {
            let symbol = try decode(lengthCode)
            if symbol < 256 {
                guard output.count < limit else { throw Self.tooLong }
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthSymbol = symbol - 257
                guard lengthSymbol < Self.lengthBase.count else { throw Self.damaged }
                let length = try Self.lengthBase[lengthSymbol] + bits(Self.lengthExtra[lengthSymbol])
                let distanceSymbol = try decode(distanceCode)
                guard distanceSymbol < Self.distanceBase.count else { throw Self.damaged }
                let distance = try Self.distanceBase[distanceSymbol] + bits(Self.distanceExtra[distanceSymbol])
                guard distance <= output.count else { throw Self.damaged }
                guard output.count + length <= limit else { throw Self.tooLong }
                // Byte by byte, because a match may overlap the bytes it copies.
                let start = output.count - distance
                for offset in 0..<length {
                    output.append(output[start + offset])
                }
            }
        }
    }

    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private mutating func dynamic() throws(ReaderError) {
        let lengthCount = try bits(5) + 257
        let distanceCount = try bits(5) + 1
        let codeLengthCount = try bits(4) + 4
        guard lengthCount <= 286, distanceCount <= 30 else { throw Self.damaged }

        var lengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            lengths[Self.codeLengthOrder[index]] = try bits(3)
        }
        let codeLengthCode = Huffman(lengths: lengths[...])
        guard codeLengthCode.unused == 0 else { throw Self.damaged }

        let total = lengthCount + distanceCount
        lengths = []
        lengths.reserveCapacity(total)
        while lengths.count < total {
            let symbol = try decode(codeLengthCode)
            if symbol < 16 {
                lengths.append(symbol)
                continue
            }
            let repeated: Int
            let count: Int
            switch symbol {
            case 16:
                guard let previous = lengths.last else { throw Self.damaged }
                repeated = previous
                count = try 3 + bits(2)
            case 17:
                repeated = 0
                count = try 3 + bits(3)
            default:
                repeated = 0
                count = try 11 + bits(7)
            }
            guard lengths.count + count <= total else { throw Self.damaged }
            lengths.append(contentsOf: repeatElement(repeated, count: count))
        }
        guard lengths[256] != 0 else { throw Self.damaged }

        // An incomplete code is only allowed when it has a single one-bit code.
        let lengthCode = Huffman(lengths: lengths[0..<lengthCount])
        guard lengthCode.unused >= 0,
              lengthCode.unused == 0 || lengthCount == lengthCode.counts[0] + lengthCode.counts[1]
        else { throw Self.damaged }
        let distanceCode = Huffman(lengths: lengths[lengthCount..<total])
        guard distanceCode.unused >= 0,
              distanceCode.unused == 0 || distanceCount == distanceCode.counts[0] + distanceCode.counts[1]
        else { throw Self.damaged }

        try codes(lengthCode, distanceCode)
    }
}

/// A canonical Huffman code, stored as the number of codes of each length
/// and the symbols in code order.
private struct Huffman: Sendable {
    static let maxBits = 15

    var counts = [Int](repeating: 0, count: maxBits + 1)
    var symbols: [Int]
    /// How many codes are left over: 0 for a complete code, more for an
    /// incomplete one, negative for an over-subscribed one.
    var unused = 1

    init(lengths: ArraySlice<Int>) {
        for length in lengths {
            counts[length] += 1
        }
        for length in 1...Self.maxBits {
            unused = (unused << 1) - counts[length]
            if unused < 0 {
                symbols = []
                return
            }
        }
        var offsets = [Int](repeating: 0, count: Self.maxBits + 1)
        for length in 1..<Self.maxBits {
            offsets[length + 1] = offsets[length] + counts[length]
        }
        symbols = [Int](repeating: 0, count: lengths.count)
        for (symbol, length) in lengths.enumerated() where length != 0 {
            symbols[offsets[length]] = symbol
            offsets[length] += 1
        }
    }

    static let fixedLengths = Huffman(lengths: (
        [Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112)
            + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8)
    )[...])
    static let fixedDistances = Huffman(lengths: [Int](repeating: 5, count: 30)[...])
}
