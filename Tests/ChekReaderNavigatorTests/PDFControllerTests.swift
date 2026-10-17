import ChekReaderCore
import ChekReaderNavigator
import ChekReaderPDF
import ChekReaderTestSupport
import Foundation
import Testing

@MainActor
@Suite struct PDFControllerTests {
    #if canImport(PDFKit)
    @Test func opensAPDFAtItsFirstPage() async throws {
        ReaderFormats.register(PDFModule.self)
        let controller = ReaderController()
        try await controller.open(.data(PDFFixture.document(pageCount: 4), fileName: "book.pdf"))
        #expect(controller.state == .ready)
        #expect(controller.format == .pdf)
        #expect(controller.location?.href == PDFModule.href)

        // Without a view, a table of contents entry still moves the location.
        let entry = try #require(controller.publication?.tableOfContents.last)
        #expect(await controller.go(to: entry))
        #expect(controller.location?.locations.fragments == ["page=3"])
    }
    #endif
}
