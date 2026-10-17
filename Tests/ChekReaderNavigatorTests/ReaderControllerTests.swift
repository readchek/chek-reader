import ChekReaderCore
import ChekReaderEPUB
import ChekReaderNavigator
import ChekReaderTestSupport
import Foundation
import Testing

@MainActor
@Suite struct ReaderControllerTests {
    @Test func unregisteredFormatFails() async {
        let controller = ReaderController()
        await #expect(throws: ReaderError.formatNotIncluded(.cb7)) {
            try await controller.open(.data(Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])))
        }
        #expect(controller.state == .failed(.formatNotIncluded(.cb7)))
        #expect(controller.format == .cb7)
    }

    @Test func unknownContentFails() async {
        let controller = ReaderController()
        await #expect(throws: ReaderError.unsupportedFormat(fileName: "a.bin")) {
            try await controller.open(.data(Data("hello".utf8), fileName: "a.bin"))
        }
    }

    @Test func remoteEPUBIsNotImplementedYet() async {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        await #expect(throws: ReaderError.notYetImplemented(.epub)) {
            try await controller.open(.remote(URL(string: "https://example.com/book.epub")!))
        }
    }

    @Test func opensAnEPUBAtItsStart() async throws {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)))
        #expect(controller.state == .ready)
        #expect(controller.format == .epub)
        #expect(controller.publication?.metadata.title == "The Lighthouse")
        #expect(controller.location?.href == "OEBPS/Text/chapter 1.xhtml")
        #expect(controller.location?.title == "Chapter One")
    }

    @Test func opensAtARequestedLocation() async throws {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        let saved = Locator(href: "OEBPS/Text/chapter2.xhtml", mediaType: "application/xhtml+xml")
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)), at: saved)
        #expect(controller.location == saved)

        // A location from another book falls back to the start.
        let foreign = Locator(href: "other.xhtml", mediaType: "application/xhtml+xml")
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)), at: foreign)
        #expect(controller.location?.href == "OEBPS/Text/chapter 1.xhtml")
    }

    @Test func movesBetweenChaptersWithoutAView() async throws {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)))

        #expect(await controller.goBackward() == false)
        #expect(await controller.goForward())
        #expect(controller.location?.href == "OEBPS/Text/chapter2.xhtml")
        #expect(await controller.goForward() == false)

        let entry = try #require(controller.publication?.tableOfContents.first?.children.first)
        #expect(await controller.go(to: entry))
        #expect(controller.location?.href == "OEBPS/Text/chapter 1.xhtml")
        #expect(controller.location?.locations.fragments == ["part2"])
        #expect(await controller.go(to: Locator(href: "nope.xhtml", mediaType: "text/html")) == false)
    }

    @Test func newerOpenWins() async throws {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        let first = Task { try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub2))) }
        while controller.state != .opening {
            await Task.yield()
        }
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)))
        _ = try? await first.value
        #expect(controller.state == .ready)
        #expect(controller.publication?.metadata.title == "The Lighthouse")
    }

    @Test func closeEndsTheSession() async throws {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)))
        await controller.close()
        #expect(controller.state == .closed)
        #expect(controller.publication == nil)
        #expect(await controller.goForward() == false)
    }

    @Test func findsPositionsAfterOpening() async throws {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)))
        for _ in 0..<1000 where controller.positions == nil {
            await Task.yield()
        }
        let positions = try #require(controller.positions)
        #expect(positions.count >= 2)
        #expect(controller.location?.locations.position == 1)
        #expect(controller.location?.locations.totalProgression == 0)

        #expect(await controller.go(toPosition: positions.count))
        #expect(controller.location?.locations.position == positions.count)
        #expect(await controller.go(toPosition: positions.count + 1) == false)
    }

    @Test func keepsPreferencesWithoutAView() async throws {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController(preferences: ReaderPreferences(fontScale: 9))
        #expect(controller.preferences.fontScale == ReaderPreferences.fontScaleRange.upperBound)
        try await controller.open(.data(EPUBFixture.book(EPUBFixture.epub3)))
        await controller.setPreferences(ReaderPreferences(fontScale: 1.25, theme: .sepia))
        #expect(controller.preferences == ReaderPreferences(fontScale: 1.25, theme: .sepia))
    }
}
