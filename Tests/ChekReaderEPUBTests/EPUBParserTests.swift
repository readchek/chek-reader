import ChekReaderCore
import ChekReaderEPUB
import Foundation
import Testing

@Suite struct EPUBParserTests {
    private func open(_ files: [(String, String)]) async throws(ReaderError) -> Publication {
        try await EPUBModule.open(.data(EPUBFixture.book(files)), format: .epub, limits: .default)
    }

    @Test func readsEPUB3Metadata() async throws {
        let metadata = try await open(EPUBFixture.epub3).metadata
        #expect(metadata.identifier == "urn:uuid:12345678-1234-1234-1234-123456789abc")
        #expect(metadata.title == "The Lighthouse")
        #expect(metadata.sortTitle == "Lighthouse, The")
        #expect(metadata.subtitle == "A Story of the Sea")
        #expect(metadata.authors == [Publication.Contributor(name: "Ada Writer", sortAs: "Writer, Ada", role: "aut")])
        #expect(metadata.contributors == [Publication.Contributor(name: "Tom Translator", role: "trl")])
        #expect(metadata.languages == ["en"])
        #expect(metadata.publishers == ["Chek Test Press"])
        #expect(metadata.published == "2026-01-02")
        #expect(metadata.modified == "2026-10-17T00:00:00Z")
        #expect(metadata.subjects == ["Fiction"])
        #expect(metadata.summary == "A short test book.")
        #expect(metadata.series == Publication.Series(name: "Sea Stories", position: 2))
        #expect(metadata.readingProgression == .leftToRight)
        #expect(metadata.layout == .reflowable)
        #expect(metadata.accessibility == Publication.Accessibility(
            conformsTo: ["EPUB Accessibility 1.1 - WCAG 2.1 Level AA"],
            accessModes: ["textual"],
            accessModesSufficient: ["textual"],
            features: ["structuralNavigation"],
            hazards: ["none"],
            summary: "Fully accessible."
        ))
    }

    @Test func buildsReadingOrderAndResources() async throws {
        let publication = try await open(EPUBFixture.epub3)
        #expect(publication.format == .epub)
        #expect(publication.warnings.isEmpty, "\(publication.warnings)")

        // Hrefs are decoded paths from the root; the non-linear notes are a resource.
        #expect(publication.readingOrder.map(\.href) == ["OEBPS/Text/chapter 1.xhtml", "OEBPS/Text/chapter2.xhtml"])
        let second = publication.readingOrder[1]
        #expect(second.mediaType == "application/xhtml+xml")
        #expect(second.properties.page == .right)
        #expect(second.properties.contains == ["scripted"])

        #expect(Set(publication.resources.map(\.href)) == [
            "OEBPS/nav.xhtml", "OEBPS/images/cover.jpg", "OEBPS/styles/book.css", "OEBPS/Text/notes.xhtml",
        ])
        #expect(publication.cover?.href == "OEBPS/images/cover.jpg")
        #expect(publication.link(for: "OEBPS/nav.xhtml")?.rels == ["contents"])

        let chapter = try await publication.data(at: "OEBPS/Text/chapter2.xhtml#top")
        #expect(String(decoding: chapter, as: UTF8.self).contains("<h1>Chapter Two</h1>"))
    }

    @Test func readsTheNavDocument() async throws {
        let publication = try await open(EPUBFixture.epub3)
        let toc = publication.tableOfContents
        #expect(toc.map(\.title) == ["Chapter One", "Later"])
        #expect(toc[0].href == "OEBPS/Text/chapter 1.xhtml")
        #expect(toc[0].children.map(\.href) == ["OEBPS/Text/chapter 1.xhtml#part2"])
        // A heading without a link takes its first child's.
        #expect(toc[1].href == "OEBPS/Text/chapter2.xhtml")
        #expect(toc[1].children.map(\.title) == ["Chapter Two"])

        #expect(publication.pageList.map(\.href) == ["OEBPS/Text/chapter 1.xhtml#page1"])
        #expect(publication.landmarks.map(\.rels) == [["bodymatter"]])
    }

    @Test func readsEPUB2WithNCX() async throws {
        let publication = try await open(EPUBFixture.epub2)
        let metadata = publication.metadata
        #expect(metadata.title == "Old Book")
        #expect(metadata.identifier == "old-book-1")
        #expect(metadata.authors == [Publication.Contributor(name: "Old Author", sortAs: "Author, Old", role: "aut")])
        #expect(metadata.contributors.map(\.role) == ["ill"])
        #expect(metadata.series == Publication.Series(name: "Old Series", position: 3.5))
        #expect(metadata.readingProgression == .rightToLeft)
        #expect(publication.cover?.href == "cover.png")

        #expect(publication.tableOfContents.map(\.title) == ["Chapter 1"])
        #expect(publication.tableOfContents[0].children.map(\.href) == ["ch1.html#s"])
        #expect(publication.pageList.map(\.href) == ["ch1.html#p1"])
        #expect(publication.landmarks == [Link(href: "ch1.html", title: "Start", rels: ["text"])])
    }

    @Test func recoversWithoutAContainerDocument() async throws {
        let files = EPUBFixture.epub2.filter { $0.0 != "META-INF/container.xml" }
        let publication = try await open(files)
        #expect(publication.metadata.title == "Old Book")
        #expect(publication.warnings.contains { $0.message.contains("Using content.opf") })
    }

    @Test func skipsMissingSpineItemsWithWarnings() async throws {
        let files = [
            ("META-INF/container.xml", EPUBFixture.container(rootfile: "content.opf")),
            ("content.opf", EPUBFixture.minimalOPF(
                manifest: """
                <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
                <item id="gone" href="gone.xhtml" media-type="application/xhtml+xml"/>
                """,
                spine: #"<itemref idref="a"/><itemref idref="unknown"/><itemref idref="gone"/>"#
            )),
            ("a.xhtml", EPUBFixture.chapter("A")),
        ]
        let publication = try await open(files)
        #expect(publication.readingOrder.map(\.href) == ["a.xhtml"])
        #expect(publication.warnings.contains { $0.message.contains("unknown") })
        #expect(publication.warnings.contains { $0.href == "gone.xhtml" })
        #expect(publication.warnings.contains { $0.message.contains("no table of contents") })
    }

    @Test func failsWithoutReadableChapters() async {
        let files = [
            ("META-INF/container.xml", EPUBFixture.container(rootfile: "content.opf")),
            ("content.opf", EPUBFixture.minimalOPF(manifest: "", spine: "")),
        ]
        let error = await #expect(throws: ReaderError.self) {
            try await open(files)
        }
        guard case .malformed(let reason) = error else {
            Issue.record("Expected a malformed error, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("spine"))
    }

    @Test func allowsFontObfuscation() async throws {
        var files = EPUBFixture.epub3
        files.append(("OEBPS/fonts/serif.otf", "font"))
        files = files.map { name, content in
            guard name == "OEBPS/content.opf" else { return (name, content) }
            return (name, content.replacingOccurrences(
                of: "</manifest>",
                with: #"<item id="font" href="fonts/serif.otf" media-type="font/otf"/></manifest>"#
            ))
        }
        files.append(("META-INF/encryption.xml", """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
            <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/serif.otf"/></enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """))
        let publication = try await open(files)
        #expect(publication.link(for: "OEBPS/fonts/serif.otf")?.properties.obfuscation == .idpf)
    }

    @Test func reportsDRM() async {
        var files = EPUBFixture.epub3
        files.append(("META-INF/rights.xml", "<rights/>"))
        files.append(("META-INF/encryption.xml", """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData>
            <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
            <enc:CipherData><enc:CipherReference URI="OEBPS/Text/chapter2.xhtml"/></enc:CipherData>
          </enc:EncryptedData>
        </encryption>
        """))
        await #expect(throws: ReaderError.drmProtected(scheme: "Adobe DRM")) {
            try await open(files)
        }
    }

    @Test func opensThroughTheRegistry() async throws {
        ReaderFormats.register(EPUBModule.self)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        try EPUBFixture.book(EPUBFixture.epub3).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let publication = try await Publication.open(.file(url))
        #expect(publication.metadata.title == "The Lighthouse")
        #expect(publication.readingOrder.count == 2)
    }

    @Test func opensFromAResourceProvider() async throws {
        // The DRM files are ignored: a provider returns decrypted resources.
        var files = EPUBFixture.epub3
        files.append(("META-INF/rights.xml", "<rights/>"))
        files.append(("META-INF/encryption.xml", "<encryption/>"))
        let provider = DictionaryProvider(files: Dictionary(files, uniquingKeysWith: { first, _ in first }))
        let publication = try await EPUBModule.open(.provider(provider), format: .epub, limits: .default)
        #expect(publication.metadata.title == "The Lighthouse")
        let css = try await publication.data(at: "OEBPS/styles/book.css")
        #expect(css == Data("body { margin: 0 }".utf8))
    }

    @Test func remoteSourcesAreNotImplementedYet() async {
        await #expect(throws: ReaderError.notYetImplemented(.epub)) {
            try await EPUBModule.open(.remote(URL(string: "https://example.com/book.epub")!), format: .epub, limits: .default)
        }
    }

    @Test func honorsCancellation() async {
        ReaderFormats.register(EPUBModule.self)
        let book = EPUBFixture.book(EPUBFixture.epub3)
        let task = Task {
            // Returns early once the task is cancelled, so opening starts cancelled.
            try? await Task.sleep(for: .seconds(60))
            return try await Publication.open(.data(book))
        }
        task.cancel()
        await #expect(throws: ReaderError.cancelled) {
            try await task.value
        }
    }
}

private struct DictionaryProvider: ResourceProvider {
    let files: [String: String]

    var format: ReaderFormat? { .epub }

    func data(at href: String) async throws -> Data {
        guard let content = files[href] else {
            throw ReaderError.malformed(reason: "No resource at \(href).")
        }
        return Data(content.utf8)
    }
}
