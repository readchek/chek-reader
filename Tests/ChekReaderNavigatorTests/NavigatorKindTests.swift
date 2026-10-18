import ChekReaderComics
import ChekReaderCore
import ChekReaderEPUB
@testable import ChekReaderNavigator
import ChekReaderTestSupport
import Foundation
import Testing

@MainActor
@Suite struct NavigatorKindTests {
    @Test func comicsShowAsImages() async throws {
        ReaderFormats.register(ComicsModule.self)
        var zip = ZIPFixture()
        zip.add("2.jpg", "two")
        zip.add("1.jpg", "one")
        let controller = ReaderController()
        try await controller.open(.data(zip.data(), fileName: "comic.cbz"))
        let publication = try #require(controller.publication)
        #expect(NavigatorKind(publication) == .images)
        #expect(controller.location?.href == "1.jpg")
        #expect(await controller.goForward())
        #expect(controller.location?.href == "2.jpg")
    }

    @Test func epubShowsInTheWebView() async throws {
        let publication = try await EPUBModule.open(.data(EPUBFixture.book(EPUBFixture.epub3)), format: .epub, limits: .default)
        #expect(NavigatorKind(publication) == .web)
    }
}
