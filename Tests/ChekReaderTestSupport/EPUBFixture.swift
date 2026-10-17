import Foundation

/// Builds small EPUBs in tests, so no books are committed.
package enum EPUBFixture {
    package static func container(rootfile: String = "OEBPS/content.opf") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(rootfile)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
    }

    package static func chapter(_ title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(title)</title></head>
        <body><h1>\(title)</h1><p>Text.</p></body></html>
        """
    }

    /// An EPUB with a stored `mimetype` first, then `files` in order.
    package static func book(_ files: [(String, String)], binary: [(String, Data)] = []) -> Data {
        var zip = ZIPFixture()
        zip.add("mimetype", "application/epub+zip")
        for (name, content) in files {
            zip.add(name, content)
        }
        for (name, content) in binary {
            zip.add(ZIPFixture.Entry(name: name, content: content))
        }
        return zip.data()
    }

    /// A complete EPUB 3 book with nav, cover, series and accessibility metadata.
    package static let epub3: [(String, String)] = [
        ("META-INF/container.xml", container()),
        ("OEBPS/content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid" xml:lang="en">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="isbn">urn:isbn:9780000000000</dc:identifier>
            <dc:identifier id="uid">urn:uuid:12345678-1234-1234-1234-123456789abc</dc:identifier>
            <dc:title id="t1">The Lighthouse</dc:title>
            <meta refines="#t1" property="title-type">main</meta>
            <meta refines="#t1" property="file-as">Lighthouse, The</meta>
            <dc:title id="t2">A Story of the Sea</dc:title>
            <meta refines="#t2" property="title-type">subtitle</meta>
            <dc:creator id="c1">Ada Writer</dc:creator>
            <meta refines="#c1" property="role" scheme="marc:relators">aut</meta>
            <meta refines="#c1" property="file-as">Writer, Ada</meta>
            <dc:creator id="c2">Tom Translator</dc:creator>
            <meta refines="#c2" property="role" scheme="marc:relators">trl</meta>
            <dc:language>en</dc:language>
            <dc:publisher>Chek Test Press</dc:publisher>
            <dc:date>2026-01-02</dc:date>
            <dc:subject>Fiction</dc:subject>
            <dc:description>A short test book.</dc:description>
            <meta property="dcterms:modified">2026-10-17T00:00:00Z</meta>
            <meta property="belongs-to-collection" id="s1">Sea Stories</meta>
            <meta refines="#s1" property="collection-type">series</meta>
            <meta refines="#s1" property="group-position">2</meta>
            <meta property="schema:accessMode">textual</meta>
            <meta property="schema:accessModeSufficient">textual</meta>
            <meta property="schema:accessibilityFeature">structuralNavigation</meta>
            <meta property="schema:accessibilityHazard">none</meta>
            <meta property="schema:accessibilitySummary">Fully accessible.</meta>
            <link rel="dcterms:conformsTo" href="EPUB Accessibility 1.1 - WCAG 2.1 Level AA"/>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="cover" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="css" href="styles/book.css" media-type="text/css"/>
            <item id="c1" href="Text/chapter%201.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="Text/chapter2.xhtml" media-type="application/xhtml+xml" properties="scripted"/>
            <item id="notes" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine page-progression-direction="ltr">
            <itemref idref="c1"/>
            <itemref idref="c2" properties="page-spread-right"/>
            <itemref idref="notes" linear="no"/>
          </spine>
        </package>
        """),
        ("OEBPS/nav.xhtml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>Contents</title></head>
        <body>
          <nav epub:type="toc" id="toc"><h1>Contents</h1>
            <ol>
              <li><a href="Text/chapter%201.xhtml">Chapter
                  One</a>
                <ol><li><a href="Text/chapter%201.xhtml#part2">Part Two</a></li></ol>
              </li>
              <li><span>Later</span>
                <ol><li><a href="Text/chapter2.xhtml">Chapter Two</a></li></ol>
              </li>
            </ol>
          </nav>
          <nav epub:type="page-list" hidden=""><ol><li><a href="Text/chapter%201.xhtml#page1">1</a></li></ol></nav>
          <nav epub:type="landmarks"><ol><li><a epub:type="bodymatter" href="Text/chapter%201.xhtml">Start</a></li></ol></nav>
        </body>
        </html>
        """),
        ("OEBPS/images/cover.jpg", "jpeg"),
        ("OEBPS/styles/book.css", "body { margin: 0 }"),
        ("OEBPS/Text/chapter 1.xhtml", chapter("Chapter One")),
        ("OEBPS/Text/chapter2.xhtml", chapter("Chapter Two")),
        ("OEBPS/Text/notes.xhtml", chapter("Notes")),
    ]

    /// An EPUB 2 book with an NCX, a guide and Calibre series metadata.
    package static let epub2: [(String, String)] = [
        ("META-INF/container.xml", container(rootfile: "content.opf")),
        ("content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
            <dc:title>Old Book</dc:title>
            <dc:creator opf:role="aut" opf:file-as="Author, Old">Old Author</dc:creator>
            <dc:creator opf:role="ill">Ilse Illustrator</dc:creator>
            <dc:identifier id="BookId">old-book-1</dc:identifier>
            <dc:language>ja</dc:language>
            <meta name="cover" content="cover-img"/>
            <meta name="calibre:series" content="Old Series"/>
            <meta name="calibre:series_index" content="3.5"/>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="cover-img" href="cover.png" media-type="image/png"/>
            <item id="ch1" href="ch1.html" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx" page-progression-direction="rtl"><itemref idref="ch1"/></spine>
          <guide><reference type="text" title="Start" href="ch1.html"/></guide>
        </package>
        """),
        ("toc.ncx", """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head/>
          <docTitle><text>Old Book</text></docTitle>
          <navMap>
            <navPoint id="n1" playOrder="1">
              <navLabel><text>Chapter 1</text></navLabel>
              <content src="ch1.html"/>
              <navPoint id="n2" playOrder="2">
                <navLabel><text>Section</text></navLabel>
                <content src="ch1.html#s"/>
              </navPoint>
            </navPoint>
          </navMap>
          <pageList>
            <pageTarget id="p1" type="normal" value="1"><navLabel><text>1</text></navLabel><content src="ch1.html#p1"/></pageTarget>
          </pageList>
        </ncx>
        """),
        ("cover.png", "png"),
        ("ch1.html", chapter("Chapter 1")),
    ]

    /// A minimal package document around `spine` and `manifest` entries.
    package static func minimalOPF(manifest: String, spine: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Minimal</dc:title></metadata>
          <manifest>\(manifest)</manifest>
          <spine>\(spine)</spine>
        </package>
        """
    }
}
