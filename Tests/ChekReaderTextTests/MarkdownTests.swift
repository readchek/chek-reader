import ChekReaderCore
@testable import ChekReaderText
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing

@Suite struct MarkdownTests {
    private func open(_ text: String) async throws -> Publication {
        try await TextModule.open(.data(Data(text.utf8), fileName: "notes.md"), format: .markdown, limits: .default)
    }

    private func html(_ markdown: String) -> String {
        MarkdownRenderer(inline: MarkdownInline()).render(MarkdownBlockParser.parse(markdown))
    }

    @Test func splitsAtHeadingsWithFrontMatter() async throws {
        let text = """
            ---
            title: "Field Notes"
            author: Ada Writer
            lang: en
            ---
            Intro text.

            # First

            See [the second](#second-part).

            ## Detail

            # Second Part

            Back to [first](#first).
            """
        let publication = try await open(text)
        #expect(publication.format == .markdown)
        #expect(publication.metadata.title == "Field Notes")
        #expect(publication.metadata.authors.map(\.name) == ["Ada Writer"])
        #expect(publication.metadata.languages == ["en"])
        #expect(publication.readingOrder.map(\.href) == ["text/chapter-0001.xhtml", "text/chapter-0002.xhtml", "text/chapter-0003.xhtml"])

        let toc = publication.tableOfContents
        #expect(toc.map(\.title) == ["First", "Second Part"])
        #expect(toc.map(\.href) == ["text/chapter-0002.xhtml#first", "text/chapter-0003.xhtml#second-part"])
        #expect(toc.first?.children.map(\.href) == ["text/chapter-0002.xhtml#detail"])

        let first = String(decoding: try await publication.data(at: "text/chapter-0002.xhtml"), as: UTF8.self)
        #expect(first.contains("<a href=\"chapter-0003.xhtml#second-part\">the second</a>"))
        #expect(first.contains("<h1 id=\"first\">First</h1>"))

        for link in publication.readingOrder {
            #expect(XMLParser(data: try await publication.data(at: link.href)).parse(), "\(link.href)")
        }
    }

    @Test func titleFallsBackToTheFirstHeading() async throws {
        #expect(try await open("# The **Title**\n\nText").metadata.title == "The Title")
    }

    @Test func rendersInlineSyntax() {
        #expect(html("Some *em*, **strong**, `a < b`, ~~gone~~ and snake_case_name.")
            == "<p>Some <em>em</em>, <strong>strong</strong>, <code>a &lt; b</code>, <del>gone</del> and snake_case_name.</p>")
        #expect(html("A [link](https://example.com \"Title\") and <https://chek.app>.")
            == "<p>A <a href=\"https://example.com\" title=\"Title\">link</a> and <a href=\"https://chek.app\">https://chek.app</a>.</p>")
        #expect(html("![A lighthouse](light.png)") == "<p><span class=\"image\">A lighthouse</span></p>")
        #expect(html("Fish &amp; chips&nbsp;&copy; &#169; &bogus; \\*not em\\*")
            == "<p>Fish &amp; chips\u{A0}© © &amp;bogus; *not em*</p>")
        #expect(html("line one  \nline two") == "<p>line one<br/>\nline two</p>")
        #expect(html("**unclosed") == "<p>**unclosed</p>")
    }

    @Test func rendersBlocks() {
        #expect(html("Title\n=====\n\nSub\n---") == "<h1>Title</h1>\n<h2>Sub</h2>")
        #expect(html("```swift\nlet a = 1 < 2\n```") == "<pre><code class=\"language-swift\">let a = 1 &lt; 2</code></pre>")
        #expect(html("    indented\n    code") == "<pre><code>indented\ncode</code></pre>")
        #expect(html("> quoted\nlazy") == "<blockquote>\n<p>quoted\nlazy</p>\n</blockquote>")
        #expect(html("- one\n- two\n  - nested") == "<ul>\n<li>one</li>\n<li>two\n<ul>\n<li>nested</li>\n</ul></li>\n</ul>")
        #expect(html("3. three\n4. four") == "<ol start=\"3\">\n<li>three</li>\n<li>four</li>\n</ol>")
        #expect(html("- a\n\n- b") == "<ul>\n<li><p>a</p></li>\n<li><p>b</p></li>\n</ul>")
        #expect(html("***") == "<hr/>")
        #expect(html("| a | b |\n|:--|--:|\n| 1 | 2 |")
            == "<table>\n<thead><tr><th style=\"text-align: left\">a</th><th style=\"text-align: right\">b</th></tr></thead>\n<tbody>\n<tr><td style=\"text-align: left\">1</td><td style=\"text-align: right\">2</td></tr>\n</tbody>\n</table>")
    }

    @Test func rawHTMLKeepsOnlyItsText() {
        #expect(html("<div align=\"center\">\n<script>alert(1)</script> Hello <!-- note -->\n</div>") == "<p>alert(1) Hello</p>")
    }

    @Test func deepNestingStaysBounded() {
        let deep = String(repeating: "> ", count: 200) + "deep"
        let rendered = html(deep)
        #expect(rendered.components(separatedBy: "<blockquote>").count - 1 == MarkdownBlockParser.maxDepth)
    }

    @Test func slugsAreUnique() {
        var slugs = Slugs()
        #expect(slugs.make(from: "Hello, World!") == "hello-world")
        #expect(slugs.make(from: "Hello World") == "hello-world-1")
        #expect(slugs.make(from: "2024") == "section-2024")
    }
}
