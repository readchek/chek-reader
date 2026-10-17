import ChekReaderCore
import Foundation
import Testing

@Suite struct FormatSnifferTests {
    /// A ZIP local file header for a stored entry, followed by its content.
    private func zipEntry(name: String, content: String) -> Data {
        var bytes: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        bytes += [20, 0, 0, 0, 0, 0]          // version, flags, method (stored)
        bytes += [0, 0, 0, 0]                  // time, date
        bytes += [0, 0, 0, 0]                  // CRC-32
        let size = UInt32(content.utf8.count)
        for _ in 0..<2 {                       // compressed and uncompressed size
            bytes += [UInt8(size & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size >> 16 & 0xFF), UInt8(size >> 24)]
        }
        bytes += [UInt8(name.utf8.count), 0, 0, 0]
        bytes += Array(name.utf8) + Array(content.utf8)
        return Data(bytes)
    }

    @Test func epubByMimetypeEntry() {
        let data = zipEntry(name: "mimetype", content: "application/epub+zip")
        #expect(FormatSniffer.format(of: data, fileName: "renamed.zip") == .epub)
    }

    @Test func zipWithoutMimetypeIsComic() {
        let data = zipEntry(name: "001.jpg", content: "x")
        #expect(FormatSniffer.format(of: data) == .cbz)
        #expect(FormatSniffer.format(of: data, fileName: "book.fb2.zip") == .fb2Zip)
    }

    @Test func magicNumbers() {
        #expect(FormatSniffer.format(of: Data("%PDF-1.7\n".utf8)) == .pdf)
        #expect(FormatSniffer.format(of: Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])) == .cbr)
        #expect(FormatSniffer.format(of: Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) == .cb7)

        var mobi = [UInt8](repeating: 0, count: 80)
        mobi.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        #expect(FormatSniffer.format(of: Data(mobi)) == .mobi)
        #expect(FormatSniffer.format(of: Data(mobi), fileName: "book.azw3") == .azw3)

        var tar = [UInt8](repeating: 0, count: 300)
        tar.replaceSubrange(257..<262, with: Array("ustar".utf8))
        #expect(FormatSniffer.format(of: Data(tar)) == .cbt)
    }

    @Test func fictionBook() {
        let xml = #"<?xml version="1.0" encoding="utf-8"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">"#
        #expect(FormatSniffer.format(of: Data(xml.utf8)) == .fb2)
    }

    @Test func contentBeatsFileName() {
        #expect(FormatSniffer.format(of: Data("%PDF-1.4".utf8), fileName: "book.epub") == .pdf)
    }

    @Test func fallsBackToFileName() {
        #expect(FormatSniffer.format(of: Data("Call me Ishmael.".utf8), fileName: "moby.TXT") == .plainText)
        #expect(FormatSniffer.format(of: Data("# Title".utf8), fileName: "notes.md") == .markdown)
        #expect(FormatSniffer.format(of: Data("hello".utf8), fileName: "unknown.bin") == nil)
    }
}
