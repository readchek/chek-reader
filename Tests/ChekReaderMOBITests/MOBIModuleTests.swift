import ChekReaderCore
import ChekReaderMOBI
import ChekReaderTestSupport
import Foundation
import Testing

@Suite struct MOBIModuleTests {
    private func open(_ data: Data, limits: ReaderLimits = .default) async throws(ReaderError) -> Publication {
        try await MOBIModule.open(.data(data, fileName: "book.mobi"), format: .mobi, limits: limits)
    }

    private func text(_ publication: Publication, _ href: String) async throws -> String {
        String(decoding: try await publication.data(at: href), as: UTF8.self)
    }

    private static let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + Array("fake jpeg".utf8)

    /// A MOBI 6 book with a guide table of contents, two chapters, links
    /// and an image. Offsets are padded to ten digits so filling them in
    /// doesn't move anything.
    private static func mobi6Book() -> (fixture: MOBIFixture, contents: Int, one: Int, two: Int) {
        let template = """
            <html><head><guide><reference type="toc" title="Contents" filepos=TTTTTTTTTT /></guide></head><body>\
            <p>Contents</p><a filepos=AAAAAAAAAA>Chapter One</a><br/><a filepos="BBBBBBBBBB">Chapter &amp; Two</a>\
            <mbp:pagebreak/><h1>Chapter One</h1><p>Hello <img recindex="00001" /> world.</p>\
            <mbp:pagebreak/><h1>Chapter Two</h1><p>Bye.</p><mbp:nu>x</mbp:nu></body></html>
            """
        func offset(_ marker: String) -> Int {
            template.utf8.distance(from: template.startIndex, to: template.range(of: marker)!.lowerBound)
        }
        func padded(_ value: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: 10 - digits.count) + digits
        }
        let contents = offset("<p>Contents")
        let one = offset("<h1>Chapter One")
        let two = offset("<h1>Chapter Two")
        let text = template
            .replacingOccurrences(of: "TTTTTTTTTT", with: padded(contents))
            .replacingOccurrences(of: "AAAAAAAAAA", with: padded(one))
            .replacingOccurrences(of: "BBBBBBBBBB", with: padded(two))
        var fixture = MOBIFixture(text: text)
        fixture.images = [jpeg]
        fixture.add(exth: 201, number: 0)
        return (fixture, contents, one, two)
    }

    @Test func readsEXTHMetadata() async throws {
        var fixture = MOBIFixture(text: "<html><body><p>Text</p></body></html>")
        fixture.add(exth: 100, "Ada Writer")
        fixture.add(exth: 100, "Tom Two")
        fixture.add(exth: 101, "Chek Test Press")
        fixture.add(exth: 103, "A short test book.")
        fixture.add(exth: 104, "9780000000002")
        fixture.add(exth: 113, "B000000000")
        fixture.add(exth: 105, "Fiction")
        fixture.add(exth: 105, "Sea")
        fixture.add(exth: 106, "2026-01-02")
        fixture.add(exth: 503, "The Lighthouse")
        fixture.add(exth: 524, "pt-BR")
        fixture.add(exth: 527, "rtl")
        let publication = try await open(fixture.data())
        let metadata = publication.metadata
        #expect(publication.format == .mobi)
        #expect(metadata.title == "The Lighthouse")
        #expect(metadata.authors == [
            Publication.Contributor(name: "Ada Writer", role: "aut"),
            Publication.Contributor(name: "Tom Two", role: "aut"),
        ])
        #expect(metadata.publishers == ["Chek Test Press"])
        #expect(metadata.summary == "A short test book.")
        #expect(metadata.identifier == "9780000000002")
        #expect(metadata.subjects == ["Fiction", "Sea"])
        #expect(metadata.published == "2026-01-02")
        #expect(metadata.languages == ["pt-BR"])
        #expect(metadata.readingProgression == .rightToLeft)
        #expect(metadata.layout == .reflowable)
    }

    @Test func fallsBackToHeaderMetadata() async throws {
        var fixture = MOBIFixture(text: "<p>Text</p>")
        fixture.fullName = "Header Title"
        fixture.locale = 0x0C
        fixture.add(exth: 122, "true")
        let publication = try await open(fixture.data())
        #expect(publication.metadata.title == "Header Title")
        #expect(publication.metadata.languages == ["fr"])
        #expect(publication.metadata.identifier?.hasPrefix("urn:sha1:") == true)
        #expect(publication.metadata.readingProgression == .auto)
        #expect(publication.metadata.layout == .fixed)

        var asin = MOBIFixture(text: "<p>Text</p>")
        asin.add(exth: 113, "B000000000")
        #expect(try await open(asin.data()).metadata.identifier == "B000000000")
    }

    @Test func splitsAtPageBreaksAndRewritesLinks() async throws {
        let (fixture, contents, one, two) = Self.mobi6Book()
        let publication = try await open(fixture.data())
        #expect(publication.warnings.isEmpty, "\(publication.warnings)")
        #expect(publication.readingOrder.map(\.href) == ["text/part0001.html", "text/part0002.html", "text/part0003.html"])
        #expect(publication.readingOrder.allSatisfy { $0.mediaType == "text/html" })

        let first = try await text(publication, "text/part0001.html")
        #expect(first.hasPrefix("<!DOCTYPE html>"))
        #expect(first.contains("<meta charset=\"utf-8\">"))
        #expect(!first.contains("<guide>"))
        #expect(first.contains("<a id=\"filepos\(contents)\"></a><p>Contents</p>"))
        #expect(first.contains("<a href=\"part0002.html#filepos\(one)\">Chapter One</a>"))
        #expect(first.contains("<a href=\"part0003.html#filepos\(two)\">Chapter &amp; Two</a>"))

        let second = try await text(publication, "text/part0002.html")
        #expect(second.contains("<a id=\"filepos\(one)\"></a><h1>Chapter One</h1>"))
        #expect(second.contains("<img src=\"../images/0001.jpg\"/>"))
        #expect(!second.contains("mbp:pagebreak"))

        let third = try await text(publication, "text/part0003.html")
        #expect(third.contains("<a id=\"filepos\(two)\"></a><h1>Chapter Two</h1><p>Bye.</p>x"))
        #expect(!third.contains("mbp:nu"))
    }

    @Test func buildsTheTableOfContentsFromTheGuide() async throws {
        let (fixture, _, one, two) = Self.mobi6Book()
        let toc = try await open(fixture.data()).tableOfContents
        #expect(toc.map(\.title) == ["Chapter One", "Chapter & Two"])
        #expect(toc.map(\.href) == ["text/part0002.html#filepos\(one)", "text/part0003.html#filepos\(two)"])
    }

    @Test func buildsTheTableOfContentsFromTheNCX() async throws {
        let (book, _, one, two) = Self.mobi6Book()
        var fixture = book
        let labels = MOBIFixture.cncx(["Part", "One", "Two"])
        fixture.ncx = MOBIFixture.index(
            tags: [MOBIFixture.IndexTag(1), MOBIFixture.IndexTag(3), MOBIFixture.IndexTag(4)],
            entries: [
                (name: "0", values: [1: [one], 3: [labels.offsets[0]], 4: [0]]),
                (name: "1", values: [1: [one], 3: [labels.offsets[1]], 4: [1]]),
                (name: "2", values: [1: [two], 3: [labels.offsets[2]], 4: [1]]),
            ],
            cncx: [labels.record]
        )
        let toc = try await open(fixture.data()).tableOfContents
        #expect(toc.map(\.title) == ["Part"])
        #expect(toc.first?.href == "text/part0002.html#filepos\(one)")
        #expect(toc.first?.children.map(\.title) == ["One", "Two"])
        #expect(toc.first?.children.map(\.href) == ["text/part0002.html#filepos\(one)", "text/part0003.html#filepos\(two)"])
    }

    @Test func servesImagesAndTheCover() async throws {
        let publication = try await open(Self.mobi6Book().fixture.data())
        #expect(publication.resources.map(\.href) == ["images/0001.jpg"])
        #expect(publication.resources.first?.mediaType == "image/jpeg")
        #expect(publication.cover?.href == "images/0001.jpg")
        #expect(try await publication.data(at: "images/0001.jpg") == Data(Self.jpeg))
    }

    @Test func decompressesPalmDOCAcrossRecordsAndStripsTrailingEntries() async throws {
        let body = (0..<40).map { "<p>Paragraph \($0) — café.</p>" }.joined()
        var fixture = MOBIFixture(text: "<html><body>\(body)</body></html>")
        fixture.compression = .palmDOC
        fixture.recordSize = 100
        // A multibyte overlap of no bytes, then one entry of two bytes plus its size.
        fixture.extraDataFlags = 0b11
        fixture.trailer = [0x00, 0xAA, 0xBB, 0x83]
        #expect(fixture.textChunks.count > 10)
        let publication = try await open(fixture.data())
        let document = try await text(publication, "text/part0001.html")
        #expect(document.contains(body))
    }

    @Test func decodesWindows1252() async throws {
        var fixture = MOBIFixture(bytes: Array("<p>".utf8) + [0x93, 0x48, 0x69, 0x94, 0x20, 0x80, 0xE9] + Array("</p>".utf8))
        fixture.encoding = 1252
        let publication = try await open(fixture.data())
        #expect(try await text(publication, "text/part0001.html").contains("<p>\u{201C}Hi\u{201D} \u{20AC}\u{E9}</p>"))
    }

    @Test func rejectsDRM() async {
        var fixture = MOBIFixture(text: "<p>Secret</p>")
        fixture.encryption = 2
        await #expect(throws: ReaderError.drmProtected(scheme: "Mobipocket DRM")) {
            try await open(fixture.data())
        }
    }

    @Test func rejectsTruncatedFiles() async {
        let data = Self.mobi6Book().fixture.data()
        for length in [10, 80, 120, data.count - 20] {
            let error = await #expect(throws: ReaderError.self) {
                try await open(data.prefix(length))
            }
            guard case .malformed = error else {
                Issue.record("Expected a malformed error for \(length) bytes, got \(String(describing: error))")
                continue
            }
        }
    }

    @Test func rejectsRecordOffsetsOutsideTheFileOrOutOfOrder() async {
        let original = Self.mobi6Book().fixture.data()
        for offset: UInt32 in [0xFFFF_FFF0, 10, 0] {
            var data = original
            MOBIFixture.setOffset(offset, ofRecord: 1, in: &data)
            let error = await #expect(throws: ReaderError.self) {
                try await open(data)
            }
            guard case .malformed = error else {
                Issue.record("Expected a malformed error for offset \(offset), got \(String(describing: error))")
                continue
            }
        }
    }

    @Test func rejectsTextRecordCountsPastTheFile() async {
        var fixture = MOBIFixture(text: "<p>Text</p>")
        fixture.recordSize = 2
        var data = fixture.data()
        // Record 0 starts after the header, record list and two bytes of padding.
        let recordCount = (Int(data[data.startIndex + 76]) << 8) | Int(data[data.startIndex + 77])
        let record0 = data.startIndex + 78 + recordCount * 8 + 2
        data[record0 + 8] = 0xFF
        data[record0 + 9] = 0xFF
        let error = await #expect(throws: ReaderError.self) {
            try await open(data)
        }
        guard case .malformed = error else {
            Issue.record("Expected a malformed error, got \(String(describing: error))")
            return
        }
    }

    @Test func enforcesLimits() async {
        var fixture = MOBIFixture(text: String(repeating: "<p>Long text.</p>", count: 20))
        await #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            try await open(fixture.data(), limits: ReaderLimits(maxUncompressedBytes: 64))
        }
        fixture.compression = .palmDOC
        await #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            try await open(fixture.data(), limits: ReaderLimits(maxUncompressedBytes: 64))
        }
        await #expect(throws: ReaderError.limitExceeded(.archiveEntries)) {
            try await open(fixture.data(), limits: ReaderLimits(maxArchiveEntries: 2))
        }
    }

    @Test func opensThroughFormatDetection() async throws {
        ReaderFormats.register(MOBIModule.self)
        let publication = try await Publication.open(.data(Self.mobi6Book().fixture.data(), fileName: "book.azw3"))
        // Detected as AZW3 by name, but the content is MOBI 6.
        #expect(publication.format == .mobi)
        #expect(publication.readingOrder.count == 3)
    }
}
