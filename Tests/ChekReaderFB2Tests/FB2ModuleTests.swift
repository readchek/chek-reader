import ChekReaderCore
import ChekReaderFB2
import ChekReaderTestSupport
import Foundation
import Testing

@Suite struct FB2ModuleTests {
    private func open(_ xml: String, limits: ReaderLimits = .default) async throws(ReaderError) -> Publication {
        try await open(Data(xml.utf8), limits: limits)
    }

    private func open(_ data: Data, limits: ReaderLimits = .default) async throws(ReaderError) -> Publication {
        try await FB2Module.open(.data(data, fileName: "book.fb2"), format: .fb2, limits: limits)
    }

    private func text(at href: String, in publication: Publication) async throws -> String {
        String(decoding: try await publication.data(at: href), as: UTF8.self)
    }

    /// The reason the book fails to open with, when it's malformed.
    private func malformedReason(_ xml: String) async -> String? {
        do {
            _ = try await open(xml)
            return nil
        } catch {
            if case .malformed(let reason) = error {
                return reason
            }
            return nil
        }
    }

    @Test func readsMetadata() async throws {
        let metadata = try await open(FB2Fixture.book).metadata
        #expect(metadata.title == "The Lighthouse")
        #expect(metadata.authors == [
            Publication.Contributor(name: "Ada K. Writer", sortAs: "Writer, Ada K.", role: "aut"),
            Publication.Contributor(name: "Ghost", role: "aut"),
        ])
        #expect(metadata.contributors == [Publication.Contributor(name: "Tom Translator", sortAs: "Translator, Tom", role: "trl")])
        #expect(metadata.subjects == ["sf", "adventure"])
        #expect(metadata.languages == ["en"])
        #expect(metadata.summary == "A short test book.\nSecond line.")
        #expect(metadata.series == Publication.Series(name: "Sea Stories", position: 2))
        // The machine-readable value wins over the text, and over publish-info's year.
        #expect(metadata.published == "2026-01-02")
        #expect(metadata.identifier == "fb2-book-1")
        #expect(metadata.publishers == ["Chek Test Press"])
        #expect(metadata.readingProgression == .auto)
        #expect(metadata.layout == .reflowable)
    }

    @Test func fallsBackToThePublishYear() async throws {
        let xml = FB2Fixture.minimal(body: "<section><p>Text</p></section>")
            .replacingOccurrences(of: "</description>", with: "<publish-info><year>1999</year></publish-info></description>")
        #expect(try await open(xml).metadata.published == "1999")
    }

    @Test func splitsTheMainBodyBySection() async throws {
        let publication = try await open(FB2Fixture.book)
        #expect(publication.format == .fb2)
        #expect(publication.warnings.isEmpty, "\(publication.warnings)")
        #expect(publication.readingOrder.map(\.href) == [
            "text/section-0001.xhtml", "text/section-0002.xhtml", "text/notes.xhtml",
        ])
        #expect(publication.readingOrder.allSatisfy { $0.mediaType == "application/xhtml+xml" })

        // The body's own title and epigraph go before the first section.
        let first = try await text(at: "text/section-0001.xhtml", in: publication)
        #expect(first.contains("<h1 class=\"title\">The Lighthouse</h1><blockquote class=\"epigraph\">"))
        #expect(first.contains("<p class=\"text-author\">Someone</p>"))
        #expect(first.contains("<section id=\"ch1\"><h1 class=\"title\">Chapter One<br/>The Shore</h1>"))
        #expect(first.contains("<h2 class=\"title\">Part One</h2><p>Text &amp; more.</p>"))
        #expect(first.contains("<link rel=\"stylesheet\" type=\"text/css\" href=\"../styles/fb2.css\"/>"))
        #expect(first.contains("lang=\"en\""))
        #expect(!first.contains("Chapter Two"))

        let second = try await text(at: "text/section-0002.xhtml", in: publication)
        #expect(second.contains("<div class=\"poem\"><div class=\"stanza\"><div class=\"v\">Line one</div></div></div>"))
        #expect(second.contains("<em>em</em> <strong>strong</strong> <del>gone</del> kept"))
        #expect(!second.contains("unknown"))
    }

    @Test func generatesWellFormedDocuments() async throws {
        let publication = try await open(FB2Fixture.book)
        for link in publication.readingOrder {
            let root = try XMLTree.parse(try await publication.data(at: link.href), limits: .default)
            #expect(root.name == "html")
        }
        let stylesheet = try await text(at: "styles/fb2.css", in: publication)
        #expect(stylesheet.contains(".epigraph"))
    }

    @Test func nestsTheTableOfContents() async throws {
        let toc = try await open(FB2Fixture.book).tableOfContents
        #expect(toc.map(\.title) == ["Chapter One The Shore", "Chapter Two", "Notes"])
        #expect(toc.map(\.href) == ["text/section-0001.xhtml", "text/section-0002.xhtml", "text/notes.xhtml"])
        // A nested section without an id gets one to point at.
        #expect(toc[0].children.map(\.title) == ["Part One", "Part Two"])
        #expect(toc[0].children.map(\.href) == ["text/section-0001.xhtml#fb2-section-1", "text/section-0001.xhtml#part2"])
        #expect(toc[1].children.isEmpty)
    }

    @Test func rewritesInternalAndNoteLinks() async throws {
        let publication = try await open(FB2Fixture.book)
        let first = try await text(at: "text/section-0001.xhtml", in: publication)
        // Within a document a link stays a fragment; across documents it names the file.
        #expect(first.contains("<a href=\"#part2\">part two</a>"))
        #expect(first.contains("<a href=\"notes.xhtml#n1\" class=\"note\" epub:type=\"noteref\">[1]</a>"))
        #expect(first.contains("<a href=\"section-0002.xhtml#ch2\">chapter two</a>"))
        #expect(first.contains("<section id=\"fb2-section-1\">"))

        let notes = try await text(at: "text/notes.xhtml", in: publication)
        #expect(notes.contains("<h1 class=\"title\">Notes</h1>"))
        #expect(notes.contains("<section id=\"n1\"><h2 class=\"title\">1</h2>"))
        #expect(notes.contains("<a href=\"section-0001.xhtml#ch1\">Back</a>"))
    }

    @Test func decodesImagesAndTheCover() async throws {
        let publication = try await open(FB2Fixture.book)
        #expect(publication.resources.map(\.href) == ["styles/fb2.css", "images/cover.jpg"])
        let cover = try #require(publication.cover)
        #expect(cover.href == "images/cover.jpg")
        #expect(cover.mediaType == "image/jpeg")
        let image = try await publication.data(at: cover.href)
        #expect(image == Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]))

        let second = try await text(at: "text/section-0002.xhtml", in: publication)
        #expect(second.contains("<img src=\"../images/cover.jpg\" alt=\"\"/>"))
    }

    @Test func keepsBinaryNamesInsideTheImagesFolder() async throws {
        let xml = FB2Fixture.minimal(
            body: "<section><image l:href=\"#../evil\"/></section>",
            extra: "<binary id=\"../evil\" content-type=\"image/png\">\(FB2Fixture.jpegBase64)</binary>"
        )
        let publication = try await open(xml)
        #expect(publication.resources.map(\.href) == ["styles/fb2.css", "images/_evil.png"])
        let document = try await text(at: "text/section-0001.xhtml", in: publication)
        #expect(document.contains("src=\"../images/_evil.png\""))
    }

    @Test func warnsAboutRepairedProblems() async throws {
        let xml = FB2Fixture.minimal(
            body: "<section><p>Text</p><image l:href=\"#missing\"/></section>",
            extra: "<binary id=\"broken\" content-type=\"image/png\">!!!</binary>"
        )
        let publication = try await open(xml)
        #expect(publication.warnings.count == 2, "\(publication.warnings)")
        #expect(publication.warnings.contains { $0.message.contains("broken") })
        #expect(publication.warnings.contains { $0.message.contains("#missing") })
        #expect(publication.resources.map(\.href) == ["styles/fb2.css"])

        let empty = try await open(FB2Fixture.minimal(body: ""))
        #expect(empty.readingOrder.map(\.href) == ["text/section-0001.xhtml"])
        #expect(empty.warnings.count == 1)
    }

    @Test func readsDeclaredEncodings() async throws {
        // "Маяк" in windows-1251, as many FictionBooks are encoded.
        var data = Data("""
            <?xml version="1.0" encoding="windows-1251"?>
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
            <description><title-info><book-title>
            """.utf8)
        data.append(contentsOf: [0xCC, 0xE0, 0xFF, 0xEA])
        data.append(Data("</book-title></title-info></description><body><section><p>Text</p></section></body></FictionBook>".utf8))
        #expect(try await open(data).metadata.title == "Маяк")
    }

    @Test func opensZippedBooks() async throws {
        var zip = ZIPFixture()
        zip.add("readme.txt", "Not the book")
        zip.add("__MACOSX/._book.fb2", "resource fork")
        zip.add("Book.FB2", FB2Fixture.book)
        let archive = zip.data()

        let publication = try await FB2Module.open(.data(archive, fileName: "book.fb2.zip"), format: .fb2Zip, limits: .default)
        #expect(publication.format == .fb2Zip)
        #expect(publication.metadata.title == "The Lighthouse")
        #expect(publication.readingOrder.count == 3)

        let server = RangeServer(archive, url: URL(string: "https://books.example/book.fb2.zip")!)
        let remote = try await FB2Module.open(.remote(server.url, server.options()), format: .fb2Zip, limits: .default)
        #expect(remote.metadata.title == "The Lighthouse")

        var empty = ZIPFixture()
        empty.add("readme.txt", "No book here")
        await #expect(throws: ReaderError.self) {
            try await FB2Module.open(.data(empty.data()), format: .fb2Zip, limits: .default)
        }
    }

    @Test func opensFromAProvider() async throws {
        struct Provider: ResourceProvider {
            let file: Data
            var format: ReaderFormat? { .fb2 }
            func data(at href: String) async throws -> Data {
                guard href == PublicationSource.wholePublicationHref else { throw ReaderError.malformed(reason: "No resource at \(href).") }
                return file
            }
        }
        let publication = try await FB2Module.open(.provider(Provider(file: Data(FB2Fixture.book.utf8))), format: .fb2, limits: .default)
        #expect(publication.metadata.title == "The Lighthouse")
    }

    @Test func rejectsMalformedBooks() async throws {
        let notFictionBook = await malformedReason("<html><body><p>Hi</p></body></html>")
        #expect(try #require(notFictionBook).contains("FictionBook"))

        let noBody = await malformedReason("""
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><description/></FictionBook>
            """)
        #expect(try #require(noBody).contains("<body>"))

        let notXML = await malformedReason("<FictionBook><body><p>unclosed</body></FictionBook>")
        #expect(notXML != nil)

        await #expect(throws: ReaderError.unsupportedFormat(fileName: nil)) {
            try await FB2Module.open(.pages(NoPages()), format: .fb2Zip, limits: .default)
        }
    }

    @Test func enforcesTheBinaryLimits() async {
        var limits = ReaderLimits()
        limits.maxUncompressedBytes = 5
        // The book itself is within every limit; only its decoded image isn't.
        await #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            try await open(FB2Fixture.book, limits: limits)
        }
    }
}

/// A page source with no pages, which FictionBooks can't come from.
private struct NoPages: PageSource {
    func pageCount() async throws -> Int { 0 }
    func page(at index: Int) async throws -> Data { Data() }
}
