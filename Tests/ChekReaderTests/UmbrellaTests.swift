import ChekReader
import Testing

@Suite struct UmbrellaTests {
    @Test func registersTheDefaultSet() {
        ReaderFormats.registerDefaults()
        for format in [ReaderFormat.epub, .pdf, .cbz, .cbt, .plainText, .markdown, .mobi, .azw3, .fb2, .fb2Zip] {
            #expect(ReaderFormats.isRegistered(format), "\(format)")
        }
    }

    @Test func archivesStayOptional() {
        #expect(!ReaderFormats.defaultModules.contains { $0.formats.contains(.cbr) })
    }
}
