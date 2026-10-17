import ChekReaderCore
import Foundation
import Testing

@Suite struct ZIPArchiveTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        var zip = ZIPFixture()
        zip.add("mimetype", "application/epub+zip")
        zip.add(ZIPFixture.Entry(name: "text/lines.txt", content: DeflateVectors.dynamicText, deflated: DeflateVectors.dynamic))
        zip.add("text/", "")

        let archive = try ZIPArchive(data: zip.data(), limits: .default)
        #expect(archive.paths == ["mimetype", "text/lines.txt"])
        #expect(try archive.read("mimetype") == Data("application/epub+zip".utf8))
        #expect(try archive.read("text/lines.txt") == DeflateVectors.dynamicText)
    }

    @Test func readsFromADataSlice() throws {
        var zip = ZIPFixture()
        zip.add("a.txt", "alpha")
        let padded = Data([1, 2, 3]) + zip.data()
        let archive = try ZIPArchive(data: padded[3...], limits: .default)
        #expect(try archive.read("a.txt") == Data("alpha".utf8))
    }

    @Test func normalizesEntryNames() throws {
        var zip = ZIPFixture()
        zip.add("./images//a.png", "a")
        zip.add("images\\b.png", "b")
        let archive = try ZIPArchive(data: zip.data(), limits: .default)
        #expect(archive.paths == ["images/a.png", "images/b.png"])
    }

    @Test(arguments: ["../evil.txt", "a/../../evil.txt", "/etc/passwd", "C:\\evil.txt"])
    func rejectsPathsOutsideTheArchive(name: String) {
        var zip = ZIPFixture()
        zip.add(name, "x")
        #expect(malformedReason { _ = try ZIPArchive(data: zip.data(), limits: .default) } != nil)
    }

    @Test func rejectsDuplicateNames() {
        var zip = ZIPFixture()
        zip.add("a.txt", "one")
        zip.add("./a.txt", "two")
        #expect(malformedReason { _ = try ZIPArchive(data: zip.data(), limits: .default) }?.contains("two entries") == true)
    }

    @Test func enforcesEntryAndSizeLimits() throws {
        var zip = ZIPFixture()
        zip.add("a.txt", "1234")
        zip.add("b.txt", "5678")
        let data = zip.data()

        #expect(throws: ReaderError.limitExceeded(.archiveEntries)) {
            try ZIPArchive(data: data, limits: ReaderLimits(maxArchiveEntries: 1))
        }
        #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            try ZIPArchive(data: data, limits: ReaderLimits(maxUncompressedBytes: 7))
        }
        let archive = try ZIPArchive(data: data, limits: ReaderLimits(maxResourceBytes: 3))
        #expect(throws: ReaderError.limitExceeded(.resourceBytes)) {
            try archive.read("a.txt")
        }
    }

    @Test func rejectsSuspiciousCompressionRatios() throws {
        var zip = ZIPFixture()
        // 22 compressed bytes claiming to expand to 2 MB.
        zip.add(ZIPFixture.Entry(
            name: "bomb.txt",
            content: DeflateVectors.fixedText,
            deflated: DeflateVectors.fixed,
            uncompressedSize: 2_000_000
        ))
        let archive = try ZIPArchive(data: zip.data(), limits: .default)
        #expect(throws: ReaderError.limitExceeded(.compressionRatio)) {
            try archive.read("bomb.txt")
        }
    }

    @Test func detectsCorruptedEntries() throws {
        var zip = ZIPFixture()
        zip.add(ZIPFixture.Entry(name: "a.txt", content: Data("alpha".utf8), crc32: 0xDEAD_BEEF))
        let archive = try ZIPArchive(data: zip.data(), limits: .default)
        #expect(malformedReason { _ = try archive.read("a.txt") }?.contains("checksum") == true)
    }

    @Test func reportsZIPEncryption() throws {
        var zip = ZIPFixture()
        zip.add(ZIPFixture.Entry(name: "a.txt", content: Data("alpha".utf8), flags: 0x0801))
        let archive = try ZIPArchive(data: zip.data(), limits: .default)
        #expect(throws: ReaderError.drmProtected(scheme: "ZIP encryption")) {
            try archive.read("a.txt")
        }
    }

    @Test func rejectsTruncatedArchives() {
        var zip = ZIPFixture()
        zip.add("a.txt", "alpha")
        let data = zip.data()
        #expect(malformedReason { _ = try ZIPArchive(data: data.prefix(40), limits: .default) } != nil)
        #expect(malformedReason { _ = try ZIPArchive(data: Data("not a zip".utf8), limits: .default) } != nil)
    }
}
