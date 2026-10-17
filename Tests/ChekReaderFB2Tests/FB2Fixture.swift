import Foundation

/// FictionBook documents built in tests, so no books are committed.
enum FB2Fixture {
    /// A ten-byte JPEG header, base64-encoded and wrapped as books wrap it.
    static let jpegBase64 = "/9j/4AAQ\n    SkZJRg=="

    /// A book with nested sections, internal and note links, a poem and a cover.
    static let book = """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description>
          <title-info>
            <genre>sf</genre>
            <genre>adventure</genre>
            <author><first-name>Ada</first-name><middle-name>K.</middle-name><last-name>Writer</last-name></author>
            <author><nickname>Ghost</nickname></author>
            <book-title>The Lighthouse</book-title>
            <annotation><p>A short test book.</p><p>Second line.</p></annotation>
            <date value="2026-01-02">2 January 2026</date>
            <coverpage><image l:href="#cover.jpg"/></coverpage>
            <lang>en</lang>
            <translator><first-name>Tom</first-name><last-name>Translator</last-name></translator>
            <sequence name="Sea Stories" number="2"/>
          </title-info>
          <document-info><id>fb2-book-1</id></document-info>
          <publish-info><publisher>Chek Test Press</publisher><year>2020</year></publish-info>
        </description>
        <body>
          <title><p>The Lighthouse</p></title>
          <epigraph><p>Light.</p><text-author>Someone</text-author></epigraph>
          <section id="ch1">
            <title><p>Chapter One</p><p>The Shore</p></title>
            <p>See <a l:href="#part2">part two</a> and a note<a l:href="#n1" type="note">[1]</a>.</p>
            <section><title><p>Part One</p></title><p>Text &amp; more.</p></section>
            <section id="part2"><title><p>Part Two</p></title><p>On to <a l:href="#ch2">chapter two</a>.</p></section>
          </section>
          <section id="ch2">
            <title><p>Chapter Two</p></title>
            <image l:href="#cover.jpg"/>
            <poem><stanza><v>Line one</v></stanza></poem>
            <p><emphasis>em</emphasis> <strong>strong</strong> <strikethrough>gone</strikethrough> <unknown>kept</unknown></p>
          </section>
        </body>
        <body name="notes">
          <title><p>Notes</p></title>
          <section id="n1"><title><p>1</p></title><p>A note. <a l:href="#ch1">Back</a></p></section>
        </body>
        <binary id="cover.jpg" content-type="image/jpeg">\(jpegBase64)</binary>
        </FictionBook>
        """

    /// A minimal book around `body`, the content of its one `<body>`, with
    /// `extra` after the body, such as `<binary>` elements.
    static func minimal(body: String, extra: String = "") -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description><title-info><book-title>Small</book-title></title-info></description>
        <body>\(body)</body>
        \(extra)
        </FictionBook>
        """
    }
}
