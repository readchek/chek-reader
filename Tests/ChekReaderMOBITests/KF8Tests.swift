import ChekReaderCore
import ChekReaderMOBI
import ChekReaderTestSupport
import Foundation
import Testing

/// Opens a small KF8 book built from skeleton, fragment, NCX and FDST
/// records, as an AZW3 file is laid out.
@Suite struct KF8Tests {
    static let skeleton0 = #"<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title><link href="kindle:flow:0001?mime=text/css" rel="stylesheet" type="text/css"/></head><body aid="0"></body></html>"#
    static let fragment0 = #"<h1>One</h1><p>See <a href="kindle:pos:fid:0001:off:0000000000">two</a>.</p><img src="kindle:embed:0001?mime=image/jpeg" alt=""/>"#
    static let skeleton1 = #"<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head><body></body></html>"#
    static let fragment1 = #"<h1>Two</h1><p id="p2">Second</p>"#
    static let css = "@font-face { font-family: F; src: url(kindle:embed:0002?mime=application/x-font-ttf); }\nh1 { color: red; }"

    static let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0] + Array("fake jpeg".utf8)
    /// The font a FONT record holds once decoded.
    static let font: [UInt8] = [0x00, 0x01, 0x00, 0x00] + Array("font".utf8)

    /// A FONT record holding ``font``, zlib-compressed in a stored block,
    /// then XOR-obfuscated with a three-byte key.
    static var fontRecord: [UInt8] {
        let zlib: [UInt8] = [0x78, 0x01, 0x01, 0x08, 0x00, 0xF7, 0xFF] + font
        let key: [UInt8] = [0x5A, 0xA5, 0x3C]
        let obfuscated = zlib.enumerated().map { $0.element ^ key[$0.offset % key.count] }
        var record = Array("FONT".utf8)
        for value: UInt32 in [UInt32(font.count), 0b11, 24 + 3, 3, 24] {
            record += (0..<4).map { UInt8(value >> (24 - 8 * $0) & 0xFF) }
        }
        return record + key + obfuscated
    }

    static func offset(of marker: String, in text: String) -> Int {
        text.utf8.distance(from: text.startIndex, to: text.range(of: marker)!.lowerBound)
    }

    struct Book {
        var fixture: MOBIFixture
        /// Where each fragment goes in its file.
        var insert0: Int
        var insert1: Int
    }

    static func book() -> Book {
        let length0 = skeleton0.utf8.count + fragment0.utf8.count
        let start1 = length0
        let insert0 = offset(of: "</body>", in: skeleton0)
        let insert1 = start1 + offset(of: "</body>", in: skeleton1)
        let flow0 = skeleton0 + fragment0 + skeleton1 + fragment1
        var fixture = MOBIFixture(text: flow0 + css)
        fixture.version = 8
        fixture.fdst = MOBIFixture.fdst(starts: [0, flow0.utf8.count], textLength: (flow0 + css).utf8.count)
        fixture.skeletonIndex = MOBIFixture.index(
            tags: [MOBIFixture.IndexTag(1), MOBIFixture.IndexTag(6, valuesPerEntry: 2)],
            entries: [
                (name: "SKEL0000000", values: [1: [1], 6: [0, skeleton0.utf8.count]]),
                (name: "SKEL0000001", values: [1: [1], 6: [start1, skeleton1.utf8.count]]),
            ]
        )
        fixture.fragmentIndex = MOBIFixture.index(
            tags: [MOBIFixture.IndexTag(2), MOBIFixture.IndexTag(3), MOBIFixture.IndexTag(4), MOBIFixture.IndexTag(6, valuesPerEntry: 2)],
            entries: [
                (name: String(insert0), values: [2: [0], 3: [0], 4: [0], 6: [skeleton0.utf8.count, fragment0.utf8.count]]),
                (name: String(insert1), values: [2: [0], 3: [1], 4: [1], 6: [start1 + skeleton1.utf8.count, fragment1.utf8.count]]),
            ]
        )
        let labels = MOBIFixture.cncx(["One", "Two"])
        fixture.ncx = MOBIFixture.index(
            tags: [MOBIFixture.IndexTag(3), MOBIFixture.IndexTag(4), MOBIFixture.IndexTag(6, valuesPerEntry: 2)],
            entries: [
                (name: "0", values: [3: [labels.offsets[0]], 4: [0], 6: [0, 0]]),
                // Twelve bytes into fragment 1 is its <p id="p2">.
                (name: "1", values: [3: [labels.offsets[1]], 4: [1], 6: [1, 12]]),
            ],
            cncx: [labels.record]
        )
        fixture.images = [jpeg, fontRecord]
        fixture.add(exth: 100, "Ada Writer")
        return Book(fixture: fixture, insert0: insert0, insert1: insert1 - start1)
    }

    private func open(_ data: Data) async throws(ReaderError) -> Publication {
        try await MOBIModule.open(.data(data, fileName: "book.mobi"), format: .mobi, limits: .default)
    }

    private func text(_ publication: Publication, _ href: String) async throws -> String {
        String(decoding: try await publication.data(at: href), as: UTF8.self)
    }

    @Test func opensKF8AsAZW3() async throws {
        let publication = try await open(Self.book().fixture.data())
        #expect(publication.format == .azw3)
        #expect(publication.warnings.isEmpty, "\(publication.warnings)")
        #expect(publication.metadata.authors.map(\.name) == ["Ada Writer"])
        #expect(publication.readingOrder.map(\.href) == ["text/part0000.xhtml", "text/part0001.xhtml"])
        #expect(publication.readingOrder.allSatisfy { $0.mediaType == "application/xhtml+xml" })
        #expect(publication.resources.map(\.href) == ["styles/flow0001.css", "images/0001.jpg", "fonts/0002.ttf"])
        #expect(publication.resources.map(\.mediaType) == ["text/css", "image/jpeg", "font/ttf"])
    }

    @Test func rebuildsFilesAndRewritesReferences() async throws {
        let book = Self.book()
        let publication = try await open(book.fixture.data())

        let first = try await text(publication, "text/part0000.xhtml")
        #expect(first.hasPrefix(#"<?xml version="1.0" encoding="utf-8"?><html"#))
        #expect(first.contains(#"<link href="../styles/flow0001.css" rel="stylesheet" type="text/css"/>"#))
        #expect(first.contains(#"<body aid="0"><h1 id="kf8pos-\#(book.insert0)">One</h1>"#))
        #expect(first.contains(#"<a href="part0001.xhtml#kf8pos-\#(book.insert1)">two</a>"#))
        #expect(first.contains(#"<img src="../images/0001.jpg" alt=""/></body></html>"#))
        #expect(!first.contains("kindle:"))

        let second = try await text(publication, "text/part0001.xhtml")
        #expect(second == #"<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head><body><h1 id="kf8pos-\#(book.insert1)">Two</h1><p id="p2">Second</p></body></html>"#)

        let css = try await text(publication, "styles/flow0001.css")
        #expect(css.contains("src: url(../fonts/0002.ttf);"))
        #expect(css.contains("h1 { color: red; }"))
    }

    @Test func decodesObfuscatedCompressedFonts() async throws {
        let publication = try await open(Self.book().fixture.data())
        #expect(try await publication.data(at: "fonts/0002.ttf") == Data(Self.font))
    }

    @Test func buildsTheTableOfContentsFromTheNCX() async throws {
        let book = Self.book()
        let toc = try await open(book.fixture.data()).tableOfContents
        #expect(toc.map(\.title) == ["One"])
        #expect(toc.first?.href == "text/part0000.xhtml#kf8pos-\(book.insert0)")
        #expect(toc.first?.children.map(\.title) == ["Two"])
        #expect(toc.first?.children.map(\.href) == ["text/part0001.xhtml#p2"])
    }

    @Test func reportsUnresolvableReferences() async throws {
        var book = Self.book()
        // Point the image at a resource the book doesn't have.
        book.fixture.images = []
        let publication = try await open(book.fixture.data())
        #expect(publication.warnings.contains { $0.message.contains("kindle:embed:0001") })
        #expect(try await text(publication, "text/part0000.xhtml").contains("kindle:embed:0001"))
    }

    @Test func rejectsMissingSkeletonIndex() async {
        var book = Self.book()
        book.fixture.skeletonIndex = []
        let error = await #expect(throws: ReaderError.self) {
            try await open(book.fixture.data())
        }
        guard case .malformed = error else {
            Issue.record("Expected a malformed error, got \(String(describing: error))")
            return
        }
    }
}
