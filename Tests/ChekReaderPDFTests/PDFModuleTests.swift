import ChekReaderCore
import ChekReaderPDF
import ChekReaderTestSupport
import Foundation
import Testing

@Suite struct PDFModuleTests {
    #if canImport(PDFKit)
    private func open(_ data: Data) async throws(ReaderError) -> Publication {
        try await PDFModule.open(.data(data, fileName: "book.pdf"), format: .pdf, limits: .default)
    }

    @Test func readsMetadataAndPages() async throws {
        let publication = try await open(PDFFixture.document())
        #expect(publication.format == .pdf)
        #expect(publication.metadata.title == "The Lighthouse")
        #expect(publication.metadata.authors.map(\.name) == ["Ada Writer", "Tom Two"])
        #expect(publication.metadata.layout == .fixed)
        #expect(publication.readingOrder.map(\.href) == [PDFModule.href])
        #expect(publication.readingOrder.first?.mediaType == "application/pdf")

        let data = try await publication.data(at: PDFModule.href)
        #expect(data.starts(with: Data("%PDF-".utf8)))
    }

    @Test func positionsArePages() async throws {
        let publication = try await open(PDFFixture.document(pageCount: 5))
        let positions = try await publication.positions()
        #expect(positions.count == 5)
        #expect(positions.locator(at: 3)?.locations.progression == 0.4)
    }

    @Test func findsTextOnPages() async throws {
        let publication = try await open(PDFFixture.document(pageCount: 4, text: [
            1: "The keeper climbed the lighthouse.",
            3: "Below, the lighthouse lamp turned on. The lighthouse shone.",
        ]))
        // Searching goes through the registry, as an app's does.
        ReaderFormats.register(PDFModule.self)
        let found = try await publication.search(for: "lighthouse")
        #expect(found.map(\.locations.fragments) == [["page=1"], ["page=3"], ["page=3"]])
        #expect(found.map(\.title) == ["Chapter One", "Chapter Two", "Chapter Two"])
        #expect(found.map(\.locations.progression) == [0, 0.5, 0.5])
        #expect(found.map { $0.text?.highlight } == ["lighthouse", "lighthouse", "lighthouse"])
        #expect(found[1].text?.before?.hasSuffix("Below, the ") == true)
        #expect(found[2].text?.before?.hasSuffix("turned on. The ") == true)
        #expect(try await publication.search(for: "LIGHTHOUSE", options: SearchOptions(caseSensitive: true)).isEmpty)
        #expect(try await publication.search(for: "lighthouse", options: SearchOptions(limit: 1)).count == 1)
    }

    @Test func outlineBecomesTheTableOfContents() async throws {
        let toc = try await open(PDFFixture.document()).tableOfContents
        #expect(toc.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(toc.map(\.href) == ["publication.pdf#page=1", "publication.pdf#page=3"])
        #expect(toc.last?.children.map(\.title) == ["Section"])

        let publication = try await open(PDFFixture.document())
        let locator = try #require(publication.locator(for: toc[1]))
        #expect(locator.locations.fragments == ["page=3"])
    }

    @Test func opensFromAProviderAndARemoteURL() async throws {
        struct Provider: ResourceProvider {
            let file: Data
            var format: ReaderFormat? { .pdf }
            func data(at href: String) async throws -> Data {
                guard href == PublicationSource.wholePublicationHref else { throw URLError(.fileDoesNotExist) }
                return file
            }
        }
        let file = PDFFixture.document()
        let provided = try await PDFModule.open(.provider(Provider(file: file)), format: .pdf, limits: .default)
        #expect(provided.metadata.title == "The Lighthouse")

        let server = RangeServer(file, url: URL(string: "https://books.example/book.pdf")!)
        let remote = try await PDFModule.open(.remote(server.url, server.options()), format: .pdf, limits: .default)
        #expect(remote.metadata.title == "The Lighthouse")
    }

    @Test func rejectsDamagedFiles() async {
        await #expect(throws: ReaderError.self) {
            try await open(Data("%PDF-1.4\nnot really".utf8))
        }
    }

    @Test func enforcesTheResourceLimit() async {
        var limits = ReaderLimits()
        limits.maxResourceBytes = 100
        await #expect(throws: ReaderError.limitExceeded(.resourceBytes)) {
            try await PDFModule.open(.data(PDFFixture.document()), format: .pdf, limits: limits)
        }
    }
    #else
    @Test func reportsThatPDFNeedsPDFKit() async {
        await #expect(throws: ReaderError.notYetImplemented(.pdf)) {
            try await PDFModule.open(.data(PDFFixture.document()), format: .pdf, limits: .default)
        }
    }
    #endif
}
