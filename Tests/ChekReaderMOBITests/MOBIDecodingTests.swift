import ChekReaderCore
@testable import ChekReaderMOBI
import ChekReaderTestSupport
import Foundation
import Testing

/// The reason of the ``ReaderError/malformed(reason:)`` error `body`
/// throws, or `nil` when it throws something else or nothing.
private func malformedReason(_ body: () throws -> Void) -> String? {
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

private func be32(_ value: UInt32) -> [UInt8] {
    (0..<4).map { UInt8(value >> (24 - 8 * $0) & 0xFF) }
}

@Suite struct PalmDOCTests {
    @Test func decodesEveryKindOfByte() throws {
        // "ABC", a back reference 3 back for 6 bytes, a space pair for " A",
        // a literal run of two high bytes, then a plain zero byte.
        let input: [UInt8] = [0x41, 0x42, 0x43, 0x80, 0x1B, 0xC1, 0x02, 0xE9, 0xFF, 0x00]
        let expected = Array("ABCABCABC A".utf8) + [0xE9, 0xFF, 0x00]
        #expect(try PalmDOC.decompress(input, limit: 100) == expected)
    }

    @Test func roundTripsTheFixtureCompressor() throws {
        let text = Array(String(repeating: "The quick brown fox — jumps over the lazy dog. ", count: 30).utf8)
        let compressed = MOBIFixture.palmDOC(text)
        #expect(compressed.count < text.count)
        #expect(try PalmDOC.decompress(compressed, limit: text.count) == text)
    }

    @Test func rejectsDamage() {
        // A back reference before any output.
        #expect(malformedReason { _ = try PalmDOC.decompress([0x80, 0x09], limit: 100) } != nil)
        // A literal run longer than the input.
        #expect(malformedReason { _ = try PalmDOC.decompress([0x05, 0x41], limit: 100) } != nil)
        // A back reference cut in half.
        #expect(malformedReason { _ = try PalmDOC.decompress([0x41, 0x80], limit: 100) } != nil)
    }

    @Test func enforcesTheLimit() {
        #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            _ = try PalmDOC.decompress([0x41, 0x42, 0x43, 0x80, 0x1B], limit: 5)
        }
    }
}

@Suite struct TrailingEntriesTests {
    @Test func stripsEntriesAndMultibyteOverlap() {
        let text = Array("Hello".utf8)
        // Multibyte: one overlap byte plus its size byte (low bits 1, so 2 bytes).
        // Then an entry of two bytes plus its one-byte size.
        let record = text + [0xC3, 0x01] + [0xAA, 0xBB, 0x83]
        #expect(TrailingEntries.textLength(of: record, flags: 0b11) == text.count)
        #expect(TrailingEntries.textLength(of: record, flags: 0b10) == text.count + 2)
        #expect(TrailingEntries.textLength(of: record, flags: 0) == record.count)
    }

    @Test func readsMultiByteSizesBackward() {
        // 200 is 0b1_1001000: the low seven bits come last, and the byte
        // with the high bit set ends the backward read.
        #expect(TrailingEntries.entrySize([0x00, 0x81, 0x48], end: 3) == 200)
        #expect(TrailingEntries.entrySize([0x85], end: 1) == 5)
        #expect(TrailingEntries.entrySize([], end: 0) == 0)
    }

    @Test func neverStripsPastTheStart() {
        #expect(TrailingEntries.textLength(of: [0x41, 0xFF], flags: 0b10) == 0)
    }
}

@Suite struct HuffCDICTests {
    /// A HUFF record where every code is 8 bits, so byte `b` selects phrase 255 - `b`.
    static let huff: [UInt8] = {
        var record = Array("HUFF".utf8) + be32(0x18) + be32(24) + be32(24 + 1024)
        for _ in 0..<256 {
            record += be32(255 << 8 | 0x80 | 8)
        }
        return record + [UInt8](repeating: 0, count: 256)
    }()

    /// A CDIC record with 256 phrases; `phrases` maps a code byte to its
    /// phrase and whether the phrase is itself compressed.
    static func cdic(_ phrases: [UInt8: (bytes: [UInt8], compressed: Bool)]) -> [UInt8] {
        var table: [UInt8] = []
        var entries: [UInt8] = []
        for index in 0..<256 {
            let phrase = phrases[UInt8(255 - index)] ?? (bytes: [], compressed: false)
            let offset = 512 + entries.count
            table += [UInt8(offset >> 8), UInt8(offset & 0xFF)]
            let header = UInt16(phrase.bytes.count) | (phrase.compressed ? 0 : 0x8000)
            entries += [UInt8(header >> 8), UInt8(header & 0xFF)] + phrase.bytes
        }
        return Array("CDIC".utf8) + be32(0x10) + be32(256) + be32(8) + table + entries
    }

    @Test func expandsNestedPhrases() throws {
        var decoder = try HuffCDIC(huff: Self.huff, cdics: [Self.cdic([
            0x00: (Array("Hello".utf8), false),
            0x01: (Array(", ".utf8), false),
            0x02: ([0x00, 0x01], true),
        ])])
        #expect(try decoder.decompress([0x02, 0x00], limit: 100) == Array("Hello, Hello".utf8))
        // Expanded phrases are remembered.
        #expect(try decoder.decompress([0x02, 0x02], limit: 100) == Array("Hello, Hello, ".utf8))
    }

    @Test func rejectsPhrasesThatContainThemselves() throws {
        var decoder = try HuffCDIC(huff: Self.huff, cdics: [Self.cdic([0x02: ([0x00, 0x02], true)])])
        #expect(malformedReason { _ = try decoder.decompress([0x02], limit: 100) } != nil)
    }

    @Test func enforcesTheLimit() throws {
        var decoder = try HuffCDIC(huff: Self.huff, cdics: [Self.cdic([0x00: (Array("Hello".utf8), false)])])
        #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            _ = try decoder.decompress([0x00, 0x00, 0x00], limit: 10)
        }
    }

    @Test func rejectsBadHeaders() {
        #expect(malformedReason { _ = try HuffCDIC(huff: Array("HUFX".utf8), cdics: []) } != nil)
        #expect(malformedReason { _ = try HuffCDIC(huff: Self.huff, cdics: [Array("CDIC".utf8)]) } != nil)
    }
}

@Suite struct MOBIIndexTests {
    @Test func readsVariableWidthIntegers() throws {
        let (value, length) = try VariableWidth.forward([0x01, 0x82], at: 0, end: 2)
        #expect(value == 130)
        #expect(length == 2)
        let (single, singleLength) = try VariableWidth.forward([0x00, 0x85], at: 1, end: 2)
        #expect(single == 5)
        #expect(singleLength == 1)
        #expect(MOBIFixture.variableWidth(130) == [0x01, 0x82])
        // No terminating byte before the end, or too many bytes.
        #expect(malformedReason { _ = try VariableWidth.forward([0x01, 0x02], at: 0, end: 2) } != nil)
        #expect(malformedReason { _ = try VariableWidth.forward([0x01, 0x82], at: 0, end: 1) } != nil)
        #expect(malformedReason { _ = try VariableWidth.forward([UInt8](repeating: 0x01, count: 6) + [0x80], at: 0, end: 7) } != nil)
    }

    @Test func decodesTagValuesWithMasks() throws {
        let definitions = [
            MOBIIndex.TagDefinition(tag: 1, valuesPerEntry: 1, mask: 0x03, isEndOfControlByte: false),
            MOBIIndex.TagDefinition(tag: 2, valuesPerEntry: 1, mask: 0x0C, isEndOfControlByte: false),
            MOBIIndex.TagDefinition(tag: 3, valuesPerEntry: 2, mask: 0x10, isEndOfControlByte: false),
            MOBIIndex.TagDefinition(tag: 0, valuesPerEntry: 0, mask: 0, isEndOfControlByte: true),
        ]
        // Tag 1's mask is all set, so a byte length (2) follows the control
        // byte; tag 2's masked value is 2, so two values; tag 3 is absent.
        let record: [UInt8] = [0x0B, 0x82, 0x85, 0x86, 0x87, 0x88]
        let tags = try MOBIIndex.tagValues(record, from: 0, to: record.count, controlByteCount: 1, definitions: definitions)
        #expect(tags == [1: [5, 6], 2: [7, 8]])

        // Values that run past the entry are damage.
        #expect(malformedReason {
            _ = try MOBIIndex.tagValues(Array(record.prefix(4)), from: 0, to: 4, controlByteCount: 1, definitions: definitions)
        } != nil)
    }

    @Test func readsAnIndexWithItsStrings() throws {
        let labels = MOBIFixture.cncx(["First", "Second"])
        let records = MOBIFixture.index(
            tags: [MOBIFixture.IndexTag(1), MOBIFixture.IndexTag(3), MOBIFixture.IndexTag(6, valuesPerEntry: 2)],
            entries: [
                (name: "a", values: [1: [10], 3: [labels.offsets[0]]]),
                (name: "bb", values: [1: [300], 3: [labels.offsets[1]], 6: [4, 5]]),
            ],
            cncx: [labels.record]
        )
        let index = try MOBIIndex(main: records[0], records: [records[1]], cncx: [records[2]], maxEntries: 10)
        #expect(index.entries.map(\.name) == [Array("a".utf8), Array("bb".utf8)])
        #expect(index.entries[0].tags == [1: [10], 3: [0]])
        #expect(index.entries[1].value(6, 1) == 5)
        #expect(index.strings[labels.offsets[1]] == Array("Second".utf8))

        #expect(throws: ReaderError.limitExceeded(.archiveEntries)) {
            _ = try MOBIIndex(main: records[0], records: [records[1]], cncx: [], maxEntries: 1)
        }
        #expect(malformedReason { _ = try MOBIIndex(main: Array(records[0].prefix(0xC4)), records: [records[1]], cncx: [], maxEntries: 10) } != nil)
    }
}

@Suite struct KF8TablesTests {
    @Test func insertsFragmentsIntoSkeletons() throws {
        let text = Array("<html><body></body></html><p>1</p><p>2</p><html><body></body></html><p>3</p>".utf8)
        let skeletons = [
            KF8Tables.Skeleton(fragmentCount: 2, start: 0, length: 26),
            KF8Tables.Skeleton(fragmentCount: 1, start: 42, length: 26),
        ]
        let fragments = [
            KF8Tables.Fragment(insertPosition: 12, fileNumber: 0, length: 8),
            KF8Tables.Fragment(insertPosition: 20, fileNumber: 0, length: 8),
            KF8Tables.Fragment(insertPosition: 54, fileNumber: 1, length: 8),
        ]
        var warnings: [String] = []
        let parts = try KF8Tables.parts(text: text, skeletons: skeletons, fragments: fragments, limit: 1000, warnings: &warnings)
        #expect(parts.map { String(decoding: $0.bytes, as: UTF8.self) } == [
            "<html><body><p>1</p><p>2</p></body></html>",
            "<html><body><p>3</p></body></html>",
        ])
        #expect(parts.map(\.start) == [0, 42])
        #expect(parts.map(\.end) == [42, 76])
        #expect(warnings.isEmpty)

        #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            var warnings: [String] = []
            _ = try KF8Tables.parts(text: text, skeletons: skeletons, fragments: fragments, limit: 50, warnings: &warnings)
        }
    }

    @Test func rejectsFragmentsOutsideTheirFile() {
        let text = Array("<html><body></body></html><p>1</p>".utf8)
        var warnings: [String] = []
        let skeleton = [KF8Tables.Skeleton(fragmentCount: 1, start: 0, length: 26)]
        #expect(malformedReason {
            _ = try KF8Tables.parts(text: text, skeletons: skeleton, fragments: [KF8Tables.Fragment(insertPosition: 40, fileNumber: 0, length: 8)], limit: 1000, warnings: &warnings)
        } != nil)
        #expect(malformedReason {
            _ = try KF8Tables.parts(text: text, skeletons: skeleton, fragments: [KF8Tables.Fragment(insertPosition: 12, fileNumber: 0, length: 80)], limit: 1000, warnings: &warnings)
        } != nil)
        #expect(malformedReason {
            _ = try KF8Tables.parts(text: text, skeletons: skeleton, fragments: [], limit: 1000, warnings: &warnings)
        } != nil)
    }

    @Test func splitsFlows() {
        let text = Array("<html/>h1{}".utf8)
        var warnings: [String] = []
        let flows = KF8Tables.flows(text: text, fdst: MOBIFixture.fdst(starts: [0, 7], textLength: text.count), warnings: &warnings)
        #expect(flows.map { String(decoding: $0, as: UTF8.self) } == ["<html/>", "h1{}"])
        #expect(warnings.isEmpty)

        let backward = KF8Tables.flows(text: text, fdst: MOBIFixture.fdst(starts: [0, 9, 7], textLength: text.count), warnings: &warnings)
        #expect(backward == [text])
        #expect(warnings.count == 1)
    }

    @Test func parsesKindleURLs() {
        #expect(KindleURL.base32("0001") == 1)
        #expect(KindleURL.base32("000V") == 31)
        #expect(KindleURL.base32("0010") == 32)
        #expect(KindleURL.base32("00W0") == nil)
        #expect(KindleURL("kindle:embed:000A?mime=image/png") == .embed(10))
        #expect(KindleURL("kindle:flow:0002?mime=text/css") == .flow(2))
        #expect(KindleURL("kindle:pos:fid:0001:off:000000000A") == .position(fragment: 1, offset: 10))
        #expect(KindleURL("kindle:pos:fid:0001") == nil)
        #expect(KindleURL("https://example.com") == nil)
    }

    @Test func findsLinkTargets() {
        let bytes = Array(#"<p>Text <b class="x">bold</b></p>"#.utf8)
        // Inside a tag: that tag.
        #expect(KF8Content.targetTag(in: bytes, at: 12)?.name == "b")
        // In text: the next start tag.
        #expect(KF8Content.targetTag(in: bytes, at: 4)?.name == "b")
        // Past the last start tag: none.
        #expect(KF8Content.targetTag(in: bytes, at: 26) == nil)
    }
}

@Suite struct MarkupTests {
    @Test func readsAttributes() throws {
        let bytes = Array(#"x <a  HREF = 'x"y' data-x=1 checked filepos=0012/> y"#.utf8)
        let tag = try #require(Markup.tag(at: 2, in: bytes))
        #expect(tag.name == "a")
        #expect(tag.kind == .start)
        #expect(tag.isSelfClosing)
        #expect(Markup.attributes(of: tag, in: bytes) == [
            Markup.Attribute(name: "href", value: #"x"y"#),
            Markup.Attribute(name: "data-x", value: "1"),
            Markup.Attribute(name: "checked", value: nil),
            Markup.Attribute(name: "filepos", value: "0012"),
        ])
    }

    @Test func skipsTextThatLooksLikeTags() {
        let bytes = Array("a < b <!-- <p> --> <p>x</p> 1<2".utf8)
        #expect(Markup.tags(in: bytes).map(\.name) == ["", "p", "p"])
        #expect(Markup.tags(in: bytes).map(\.kind) == [.other, .start, .end])
    }

    @Test func decodesWindows1252() {
        #expect(MOBITextEncoding.cp1252.decode([0x41, 0x80, 0x93, 0x81, 0xFF]) == "A\u{20AC}\u{201C}\u{FFFD}\u{FF}")
    }
}

@Suite struct MOBIFontTests {
    @Test func decodesPlainAndObfuscatedFonts() throws {
        let font: [UInt8] = Array("OTTO".utf8) + [1, 2, 3, 4]
        let plain = Array("FONT".utf8) + be32(8) + be32(0) + be32(24) + be32(0) + be32(0) + font
        let decoded = try MOBIFont.decode(plain, limits: .default)
        #expect(decoded.data == font)
        #expect(decoded.fileExtension == "otf")

        let key: [UInt8] = [0x0F, 0xF0]
        let obfuscated = font.enumerated().map { $0.element ^ key[$0.offset % 2] }
        let record = Array("FONT".utf8) + be32(8) + be32(2) + be32(26) + be32(2) + be32(24) + key + obfuscated
        #expect(try MOBIFont.decode(record, limits: .default).data == font)
    }

    @Test func rejectsDamagedFonts() {
        let header = Array("FONT".utf8) + be32(8) + be32(2) + be32(24) + be32(4) + be32(200)
        #expect(malformedReason { _ = try MOBIFont.decode(header + [0, 1, 0, 0], limits: .default) } != nil)
        let unknown = Array("FONT".utf8) + be32(4) + be32(0) + be32(24) + be32(0) + be32(0) + Array("junk".utf8)
        #expect(malformedReason { _ = try MOBIFont.decode(unknown, limits: .default) } != nil)
    }
}
