@testable import ChekReaderCore
import Testing

@Suite struct HTMLTextTests {
    @Test func keepsOnlyTheBodyText() {
        let html = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Ignored</title><style>p { color: red }</style></head>
        <body>
          <h1 title="a > b">Chapter   One</h1>
          <!-- a <p>comment</p> -->
          <p>It was a dark and
             stormy night; <script>var x = "<p>not text</p>";</script>Tom &amp; Jerry &lt;3 caf&eacute; &#8212; &#x201C;yes&#x201D;.</p>
          <p>Next.</p>
        </body></html>
        """
        #expect(HTMLText.flatten(html) == "Chapter One It was a dark and stormy night; Tom & Jerry <3 café — “yes”. Next.")
    }

    @Test func readsCDATAAsTextAndCollapsesNonBreakingSpaces() {
        #expect(HTMLText.flatten("<body><p><![CDATA[a < b]]>&nbsp; c</p></body>") == "a < b c")
    }

    @Test func joinsAdjacentElementsLikeTheReaderScript() {
        // The script concatenates text nodes, so no space appears where the markup has none.
        #expect(HTMLText.flatten("<body><h1>One</h1><p>Two</p>\n<p>Three</p></body>") == "OneTwo Three")
    }
}
