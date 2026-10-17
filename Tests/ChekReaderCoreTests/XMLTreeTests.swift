import ChekReaderCore
import Foundation
import Testing

@Suite struct XMLTreeTests {
    @Test func matchesNamesWithoutPrefixes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf" version="2.0">
          <metadata>
            <dc:title>The <![CDATA[Title]]></dc:title>
            <dc:creator opf:role="aut" id="c1">Ada</dc:creator>
          </metadata>
        </package>
        """
        let root = try XMLTree.parse(Data(xml.utf8), limits: .default)
        #expect(root.name == "package")
        #expect(root.namespace == "http://www.idpf.org/2007/opf")
        #expect(root.attribute("version") == "2.0")
        let metadata = try #require(root.firstElement(named: "metadata"))
        #expect(metadata.firstElement(named: "title")?.trimmedText == "The Title")
        let creator = try #require(root.firstDescendant(named: "creator"))
        #expect(creator.attribute("role") == "aut")
        #expect(creator.attribute("id") == "c1")
    }

    @Test func collapsesWhitespaceAcrossElements() throws {
        let root = try XMLTree.parse(Data("<a>  Hello <b>big</b>\n   world  </a>".utf8), limits: .default)
        #expect(root.trimmedText == "Hello big world")
        #expect(root.elements(named: "b").count == 1)
    }

    @Test func enforcesTheDepthLimit() {
        let xml = String(repeating: "<a>", count: 5) + String(repeating: "</a>", count: 5)
        #expect(throws: ReaderError.limitExceeded(.xmlDepth)) {
            try XMLTree.parse(Data(xml.utf8), limits: ReaderLimits(maxXMLDepth: 4))
        }
        #expect(throws: Never.self) {
            try XMLTree.parse(Data(xml.utf8), limits: ReaderLimits(maxXMLDepth: 5))
        }
    }

    @Test func rejectsEntityDeclarations() {
        let xml = #"<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "aaaaaaaa"><!ENTITY b "&a;&a;&a;&a;">]><x>&b;</x>"#
        #expect(malformedReason { _ = try XMLTree.parse(Data(xml.utf8), limits: .default) }?.contains("entities") == true)
    }

    @Test func rejectsMalformedDocuments() {
        #expect(malformedReason { _ = try XMLTree.parse(Data("<a><b></a>".utf8), limits: .default) } != nil)
        #expect(malformedReason { _ = try XMLTree.parse(Data("".utf8), limits: .default) } != nil)
    }
}
