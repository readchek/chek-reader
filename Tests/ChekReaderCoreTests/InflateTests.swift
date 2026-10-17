import ChekReaderCore
import Foundation
import Testing

@Suite struct InflateTests {
    private static let vectors: [(compressed: Data, text: Data)] = [
        (DeflateVectors.fixed, DeflateVectors.fixedText),
        (DeflateVectors.dynamic, DeflateVectors.dynamicText),
        (DeflateVectors.stored, DeflateVectors.storedText),
    ]

    @Test(arguments: 0..<3)
    func decodesReferenceData(index: Int) throws {
        let (compressed, text) = Self.vectors[index]
        #expect(try Inflate.swiftDecompress(compressed, expectedSize: text.count) == text)
        #expect(try Inflate.decompress(compressed, expectedSize: text.count) == text)
    }

    @Test func rejectsOutputLongerThanRecorded() {
        let text = DeflateVectors.dynamicText
        #expect(malformedReason { _ = try Inflate.swiftDecompress(DeflateVectors.dynamic, expectedSize: text.count - 1) } != nil)
        #expect(malformedReason { _ = try Inflate.decompress(DeflateVectors.dynamic, expectedSize: text.count - 1) } != nil)
    }

    @Test func rejectsOutputShorterThanRecorded() {
        let text = DeflateVectors.dynamicText
        #expect(malformedReason { _ = try Inflate.swiftDecompress(DeflateVectors.dynamic, expectedSize: text.count + 1) } != nil)
        #expect(malformedReason { _ = try Inflate.decompress(DeflateVectors.dynamic, expectedSize: text.count + 1) } != nil)
    }

    @Test func rejectsTruncatedAndInvalidData() {
        let truncated = DeflateVectors.dynamic.prefix(100)
        let size = DeflateVectors.dynamicText.count
        #expect(malformedReason { _ = try Inflate.swiftDecompress(truncated, expectedSize: size) } != nil)
        #expect(malformedReason { _ = try Inflate.decompress(truncated, expectedSize: size) } != nil)
        // Block type 3 is reserved.
        #expect(malformedReason { _ = try Inflate.swiftDecompress(Data([0xFF, 0xFF, 0xFF]), expectedSize: 10) } != nil)
        #expect(malformedReason { _ = try Inflate.decompress(Data([0xFF, 0xFF, 0xFF]), expectedSize: 10) } != nil)
        // A stored block whose length doesn't match its complement.
        #expect(malformedReason { _ = try Inflate.swiftDecompress(Data([0x01, 0x05, 0x00, 0x00, 0x00]) + DeflateVectors.storedText, expectedSize: 5) } != nil)
    }

    @Test func checksumMatchesZlib() {
        #expect(CRC32.checksum(Data("hello".utf8)) == 0x3610_A686)
        #expect(CRC32.checksum(Data()) == 0)
    }
}
