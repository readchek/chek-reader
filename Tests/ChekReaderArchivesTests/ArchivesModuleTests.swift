import ChekReaderArchives
import ChekReaderCore
import Testing
import Foundation

/// The smallest valid PNG header, enough for a page's bytes in tests.
private let page = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
private let secondPage = page + Data([1, 2, 3])

private let comicInfo = """
    <?xml version="1.0"?>
    <ComicInfo><Title>The Long Night</Title><Manga>YesAndRightToLeft</Manga></ComicInfo>
    """

@Suite struct ArchivesModuleTests {
    @Test func opensACBR() async throws {
        let data = RARFixture.archive([
            ("Night/p10.jpg", page), ("Night/p2.jpg", secondPage), ("Night/p1.png", page),
            ("ComicInfo.xml", Data(comicInfo.utf8)), ("notes.txt", Data("x".utf8)),
        ])
        #expect(try await FormatSniffer.format(of: .data(data)) == .cbr)
        let publication = try await ArchivesModule.open(.data(data, fileName: "night.cbr"), format: .cbr, limits: .default)
        #expect(publication.format == .cbr)
        #expect(publication.readingOrder.map(\.href) == ["Night/p1.png", "Night/p2.jpg", "Night/p10.jpg"])
        #expect(publication.metadata.title == "The Long Night")
        #expect(publication.metadata.readingProgression == .rightToLeft)
        #expect(try await publication.data(at: "Night/p2.jpg") == secondPage)
        #expect(try await publication.data(at: "Night/p1.png") == page)
    }

    @Test func opensACB7() async throws {
        let data = SevenZipFixture.archive([("02.jpg", secondPage), ("01.jpg", page), ("ComicInfo.xml", Data(comicInfo.utf8))])
        #expect(try await FormatSniffer.format(of: .data(data)) == .cb7)
        let publication = try await ArchivesModule.open(.data(data, fileName: "night.cb7"), format: .cb7, limits: .default)
        #expect(publication.readingOrder.map(\.href) == ["01.jpg", "02.jpg"])
        #expect(publication.metadata.title == "The Long Night")
        #expect(try await publication.data(at: "02.jpg") == secondPage)
        #expect(try await publication.positions().count == 2)
    }

    @Test func enforcesLimitsAndRejectsDamage() async throws {
        let data = RARFixture.archive([("01.jpg", page), ("02.jpg", page)])
        var limits = ReaderLimits.default
        limits.maxArchiveEntries = 1
        await #expect(throws: ReaderError.limitExceeded(.archiveEntries)) {
            try await ArchivesModule.open(.data(data), format: .cbr, limits: limits)
        }

        // A header CRC that doesn't match is how a damaged archive shows.
        var damaged = data
        damaged[20] ^= 0xFF
        await #expect(throws: ReaderError.self) {
            try await ArchivesModule.open(.data(damaged), format: .cbr, limits: .default)
        }
        // Cut into the last page, past the end block.
        let truncated = data.prefix(data.count - 12)
        let publication = try await ArchivesModule.open(.data(truncated), format: .cbr, limits: .default)
        await #expect(throws: ReaderError.self) {
            try await publication.data(at: "02.jpg")
        }
    }
}
