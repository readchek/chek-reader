import ChekReaderCore
import Foundation

/// The reason of the ``ReaderError/malformed(reason:)`` error `body` throws,
/// or `nil` when it throws something else or nothing.
func malformedReason(_ body: () throws -> Void) -> String? {
    do {
        try body()
        return nil
    } catch {
        if case .malformed(let reason) = error as? ReaderError {
            return reason
        }
        return nil
    }
}

/// Raw DEFLATE vectors made with zlib, so both decoders are checked against
/// a reference encoder.
enum DeflateVectors {
    /// Compressed with fixed Huffman codes.
    static let fixedText = Data("Call me Ishmael. Call me Ishmael. Call me Ishmael.".utf8)
    static let fixed = Data([
        115, 78, 204, 201, 81, 200, 77, 85, 240, 44, 206, 200, 77, 76, 205, 209, 83, 112, 38, 36, 0, 0,
    ])

    /// Compressed with dynamic Huffman codes.
    static let dynamicText = Data((0..<200).map { "Line \($0): the quick brown fox jumps over the lazy dog.\n" }.joined().utf8)
    static let dynamic = Data(base64Encoded: """
        ndrZcRNBAEXRf6KYCKh5vTcxOAkMAsxiYWOzRU9BBpxv1fvSKWnmdt/c3V+O89Xx9OFyPDzfvfl03D5ef9wf764/j4/PX75+O67fL4//Pv78+vev4+31/csXN39HkVGRUZVRk1GX0ZDRlNGS0aYv10iQiRCKkIoQi5CLEIyQjBCNkI1CNor9XpCNQjYK2Shko5CNQjYK2Shko5KNSjaq/ZmQjUo2KtmoZKOSjUo2KtloZKORjUY2mj1pkI1GNhrZaGSjkY1GNjrZ6GSjk41ONro9hpKNTjY62ehko5ONQTYG2RhkY5CNQTaGvaOQjUE2BtkYZGOSjUk2JtmYZGOSjUk2pr3Ako1JNibZWGRjkY1FNhbZWGRjkY1FNpbVDbKxyMYmG5tsbLKxycYmG5tsbLKxyca29IXty+LXafXrtPx1Wv86LYCdVsBOS2CnNbDTIthpSjSRmhKMpFhJMZNiJ8VQiqUUU6m10lgsTcGSbkqsl8aCaayYxpJprJnGommsmsayaaybpuKBiymxdBprp7F4GqunsXwa66exgBorqLGEmobncqbEKmoso8Y6aiykxkpqLKXGWmospsZqajoe35oSC6qxohpLqrGmGouqsaoay6qxrhoLqxl4ym9KrK3G4mqsrsbyaqyvxgJrrLDGEmussWbiZRBTYpk11lljoTVWWmOpNdZaY7E1VltjuTUL7wyZEiuuseQaa66x6BqrrrHsGuuusfAaK6/ZeLXsf5X8AQ==
        """, options: .ignoreUnknownCharacters)!

    /// A stored block: header, length, its complement, then the bytes.
    static let storedText = Data("hello".utf8)
    static let stored = Data([0x01, 0x05, 0x00, 0xFA, 0xFF]) + storedText
}
