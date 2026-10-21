import ChekReaderCore
import ChekReaderEPUB
import ChekReaderTestSupport
import Foundation
import Testing

@Suite struct SearchTests {
    private func open() async throws(ReaderError) -> Publication {
        try await EPUBModule.open(.data(EPUBFixture.book(book)), format: .epub, limits: .default)
    }

    private var book: [(String, String)] {
        [
            ("META-INF/container.xml", EPUBFixture.container()),
            ("OEBPS/content.opf", EPUBFixture.minimalOPF(
                manifest: """
                <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
                <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
                <item id="art" href="art.png" media-type="image/png"/>
                """,
                spine: """
                <itemref idref="one"/><itemref idref="two"/>
                """
            )),
            ("OEBPS/one.xhtml", """
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title>
            <script>var lighthouse = 1;</script></head>
            <body><h1>One</h1>
            <p>The keeper climbed the lighthouse at dusk.</p>
            <p>Below, the Lighthouse lamp turned on.</p></body></html>
            """),
            ("OEBPS/two.xhtml", """
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Two</title></head>
            <body><h1>Two</h1><p>A caf&eacute; by the sea sold coffee to the lighthouse keeper.</p></body></html>
            """),
            ("OEBPS/art.png", "png"),
        ]
    }

    @Test func findsEveryMatchInReadingOrderWithContext() async throws {
        let found = try await open().search(for: "lighthouse")
        #expect(found.map(\.href) == ["OEBPS/one.xhtml", "OEBPS/one.xhtml", "OEBPS/two.xhtml"])
        #expect(found.map { $0.text?.highlight } == ["lighthouse", "Lighthouse", "lighthouse"])
        #expect(found[0].text?.before == "One The keeper climbed the ")
        #expect(found[0].text?.after == " at dusk. Below, the Lighthouse ")
        #expect(found[0].locations.fragments.isEmpty)
        #expect(found[0].locations.progression ?? 0 < found[1].locations.progression ?? 0)
        #expect(found[0].mediaType == "application/xhtml+xml")
    }

    @Test func honorsCaseDiacriticsAndLimits() async throws {
        let publication = try await open()
        #expect(try await publication.search(for: "Lighthouse", options: SearchOptions(caseSensitive: true)).count == 1)
        #expect(try await publication.search(for: "cafe").map { $0.text?.highlight } == ["café"])
        #expect(try await publication.search(for: "cafe", options: SearchOptions(diacriticSensitive: true)).isEmpty)
        #expect(try await publication.search(for: "lighthouse", options: SearchOptions(limit: 2)).count == 2)
        #expect(try await publication.search(for: "  \n").isEmpty)
    }
}
