import ChekReaderCore
import ChekReaderTestSupport
@testable import ChekReaderText
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing

@Suite struct PlainTextTests {
    private func open(_ text: String, fileName: String = "book.txt") async throws -> Publication {
        try await TextModule.open(.data(Data(text.utf8), fileName: fileName), format: .plainText, limits: .default)
    }

    private func html(_ publication: Publication, _ index: Int) async throws -> String {
        String(decoding: try await publication.data(at: publication.readingOrder[index].href), as: UTF8.self)
    }

    @Test func splitsAtChapterHeadings() async throws {
        let text = """
            Title: The Lighthouse
            Author: Ada Writer

            CHAPTER I

            The keeper climbed
            the stairs.

            It was late & dark.

            CHAPTER II

            Morning <came>.
            """
        let publication = try await open(text)
        #expect(publication.format == .plainText)
        #expect(publication.metadata.title == "The Lighthouse")
        #expect(publication.metadata.authors.map(\.name) == ["Ada Writer"])
        #expect(publication.readingOrder.count == 3)
        #expect(publication.tableOfContents.map(\.title) == ["CHAPTER I", "CHAPTER II"])
        #expect(publication.tableOfContents.map(\.href) == ["text/part-0002.xhtml", "text/part-0003.xhtml"])

        let chapter = try await html(publication, 1)
        #expect(chapter.contains("<h2 id=\"chapter\">CHAPTER I</h2>"))
        // Wrapped lines join into one paragraph, and text is escaped.
        #expect(chapter.contains("<p class=\"plain\">The keeper climbed the stairs.</p>"))
        #expect(chapter.contains("It was late &amp; dark."))
        #expect(try await html(publication, 2).contains("Morning &lt;came&gt;."))
    }

    @Test func linesAreParagraphsWithoutBlankLines() {
        let paragraphs = PlainTextParser.paragraphs("one\ntwo\nthree".split(separator: "\n"))
        #expect(paragraphs == ["one", "two", "three"])
    }

    @Test func longTextWithoutHeadingsIsSplitIntoParts() async throws {
        let paragraph = String(repeating: "word ", count: 2_000)
        let text = Array(repeating: paragraph, count: 12).joined(separator: "\n\n")
        let publication = try await open(text, fileName: "Long_Story.txt")
        // Parts close once they pass the length, so 12 paragraphs of
        // 10,000 characters make two parts of six.
        #expect(publication.readingOrder.count == 2)
        #expect(publication.tableOfContents.isEmpty)
        #expect(publication.metadata.title == "Long Story")
    }

    @Test func decodesOtherEncodings() async throws {
        var utf16 = Data([0xFF, 0xFE])
        utf16.append("Café".data(using: .utf16LittleEndian)!)
        let fromUTF16 = try await TextModule.open(.data(utf16, fileName: "a.txt"), format: .plainText, limits: .default)
        #expect(try await html(fromUTF16, 0).contains("Café"))

        let cp1252 = Data([0x43, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])
        let fromCP1252 = try await TextModule.open(.data(cp1252, fileName: "a.txt"), format: .plainText, limits: .default)
        #expect(try await html(fromCP1252, 0).contains("Café “q”"))
    }

    @Test func chaptersAreValidXML() async throws {
        let publication = try await open("CHAPTER 1\n\nA \u{1} b\n\nCHAPTER 2\n\n<&>")
        for link in publication.readingOrder {
            let data = try await publication.data(at: link.href)
            #expect(XMLParser(data: data).parse(), "\(link.href)")
        }
    }

    @Test func headingDetection() {
        #expect(PlainTextParser.isHeading("Chapter 12. The Storm"))
        #expect(PlainTextParser.isHeading("XIV"))
        #expect(!PlainTextParser.isHeading("I went to the shore."))
        #expect(!PlainTextParser.isHeading("Chapter after chapter the story went on and on, never ending, until the keeper slept at last."))
    }
}
