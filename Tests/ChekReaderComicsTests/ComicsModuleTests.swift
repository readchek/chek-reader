import ChekReaderComics
import ChekReaderCore
import ChekReaderTestSupport
import Foundation
import Testing

/// The smallest valid PNG header, enough for a page's bytes in tests.
private let page = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

private let comicInfo = """
    <?xml version="1.0"?>
    <ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <Title>The Long Night</Title>
      <Series>Lighthouse Keepers</Series>
      <Number>3</Number>
      <Summary>Storms.</Summary>
      <Writer>Ada Writer, Bo Second</Writer>
      <Penciller>Cy Artist</Penciller>
      <Publisher>Chek Comics</Publisher>
      <Genre>Drama, Sea</Genre>
      <LanguageISO>ja</LanguageISO>
      <Year>2024</Year>
      <Month>5</Month>
      <Manga>YesAndRightToLeft</Manga>
      <Pages>
        <Page Image="0" />
        <Page Image="1" Type="FrontCover" />
        <Page Image="2" Bookmark="Chapter 2" />
      </Pages>
    </ComicInfo>
    """

@Suite struct ComicsModuleTests {
    private func cbz(_ names: [String], info: String? = nil) -> Data {
        var zip = ZIPFixture()
        for name in names {
            zip.add(ZIPFixture.Entry(name: name, content: page))
        }
        if let info {
            zip.add("ComicInfo.xml", info)
        }
        return zip.data()
    }

    @Test func ordersPagesNaturally() async throws {
        let data = cbz(["p10.jpg", "p2.jpg", "p1.png", "notes.txt", "__MACOSX/._p1.png", ".hidden.jpg", "P3.JPG"])
        let publication = try await ComicsModule.open(.data(data, fileName: "Night_Watch.cbz"), format: .cbz, limits: .default)
        #expect(publication.readingOrder.map(\.href) == ["p1.png", "p2.jpg", "P3.JPG", "p10.jpg"])
        #expect(publication.readingOrder.first?.mediaType == "image/png")
        #expect(publication.metadata.layout == .fixed)
        #expect(publication.metadata.title == "Night Watch")
        #expect(publication.cover?.href == "p1.png")
        #expect(publication.tableOfContents.isEmpty)

        let positions = try await publication.positions()
        #expect(positions.count == 4)
        #expect(try await publication.data(at: "p2.jpg") == page)
    }

    @Test func readsComicInfo() async throws {
        let data = cbz(["01.jpg", "02.jpg", "03.jpg"], info: comicInfo)
        let publication = try await ComicsModule.open(.data(data), format: .cbz, limits: .default)
        let metadata = publication.metadata
        #expect(metadata.title == "The Long Night")
        #expect(metadata.series == Publication.Series(name: "Lighthouse Keepers", position: 3))
        #expect(metadata.authors.map(\.name) == ["Ada Writer", "Bo Second"])
        #expect(metadata.contributors == [Publication.Contributor(name: "Cy Artist", role: "ill")])
        #expect(metadata.publishers == ["Chek Comics"])
        #expect(metadata.subjects == ["Drama", "Sea"])
        #expect(metadata.languages == ["ja"])
        #expect(metadata.published == "2024-05")
        #expect(metadata.readingProgression == .rightToLeft)
        #expect(publication.cover?.href == "02.jpg")
        #expect(publication.tableOfContents.map(\.title) == ["Chapter 2"])
        #expect(publication.tableOfContents.map(\.href) == ["03.jpg"])
    }

    @Test func foldersBecomeChapters() async throws {
        let data = cbz(["Vol 1/Ch 10/1.jpg", "Vol 1/Ch 2/1.jpg", "Vol 1/Ch 2/2.jpg"])
        let publication = try await ComicsModule.open(.data(data), format: .cbz, limits: .default)
        #expect(publication.readingOrder.map(\.href) == ["Vol 1/Ch 2/1.jpg", "Vol 1/Ch 2/2.jpg", "Vol 1/Ch 10/1.jpg"])
        #expect(publication.tableOfContents.map(\.title) == ["Ch 2", "Ch 10"])
    }

    @Test func brokenComicInfoIsAWarning() async throws {
        let data = cbz(["1.jpg"], info: "<ComicInfo><Title>Unclosed")
        let publication = try await ComicsModule.open(.data(data), format: .cbz, limits: .default)
        #expect(publication.readingOrder.count == 1)
        #expect(publication.warnings.count == 1)
    }

    @Test func comicWithoutImagesIsMalformed() async {
        let error = await #expect(throws: ReaderError.self) {
            try await ComicsModule.open(.data(cbz(["readme.txt"])), format: .cbz, limits: .default)
        }
        #expect(error?.isMalformed == true)
    }

    @Test func opensACBZFromAURL() async throws {
        let server = RangeServer(cbz(["1.jpg", "2.jpg"]), url: URL(string: "https://books.example/comic.cbz")!)
        let publication = try await ComicsModule.open(.remote(server.url, server.options()), format: .cbz, limits: .default)
        #expect(publication.readingOrder.count == 2)
        #expect(try await publication.data(at: "2.jpg") == page)
    }

    @Test func opensACBT() async throws {
        var tar = TARFixture()
        tar.add("comic/02.jpg", page)
        tar.add("comic/01.jpg", page)
        let longName = "comic/" + String(repeating: "x", count: 120) + "/03.jpg"
        tar.add(longName, page)
        tar.add("ComicInfo.xml", comicInfo)
        let publication = try await ComicsModule.open(.data(tar.data(), fileName: "a.cbt"), format: .cbt, limits: .default)
        #expect(publication.format == .cbt)
        #expect(publication.readingOrder.map(\.href) == ["comic/01.jpg", "comic/02.jpg", longName])
        #expect(publication.metadata.title == "The Long Night")
        #expect(try await publication.data(at: "comic/02.jpg") == page)
    }

    @Test func rejectsADamagedCBT() async {
        var tar = TARFixture()
        tar.add("1.jpg", page, checksum: 1)
        let error = await #expect(throws: ReaderError.self) {
            try await ComicsModule.open(.data(tar.data()), format: .cbt, limits: .default)
        }
        #expect(error?.isMalformed == true)
    }

    @Test func enforcesTARLimits() async {
        var tar = TARFixture()
        for index in 0..<5 {
            tar.add("\(index).jpg", page)
        }
        var limits = ReaderLimits()
        limits.maxArchiveEntries = 3
        await #expect(throws: ReaderError.limitExceeded(.archiveEntries)) {
            try await ComicsModule.open(.data(tar.data()), format: .cbt, limits: limits)
        }
        limits = ReaderLimits()
        limits.maxResourceBytes = 4
        await #expect(throws: ReaderError.limitExceeded(.resourceBytes)) {
            try await ComicsModule.open(.data(tar.data()), format: .cbt, limits: limits)
        }
    }

    @Test func opensStreamedPages() async throws {
        struct Pages: PageSource {
            func pageCount() async throws -> Int { 3 }
            func page(at index: Int) async throws -> Data { Data([UInt8(index)]) }
        }
        let publication = try await ComicsModule.open(.pages(Pages()), format: .cbz, limits: .default)
        #expect(publication.readingOrder.map(\.href) == ["pages/1", "pages/2", "pages/3"])
        #expect(try await publication.data(at: "pages/3") == Data([2]))
        await #expect(throws: ReaderError.self) {
            try await publication.data(at: "pages/4")
        }
    }
}

extension ReaderError {
    fileprivate var isMalformed: Bool {
        if case .malformed = self { true } else { false }
    }
}
