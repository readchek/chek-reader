import ChekReaderCore
import Testing

private enum StubModule: ReaderFormatModule {
    static let formats: [ReaderFormat] = [.fb2]
}

@Suite struct ReaderFormatsTests {
    @Test func unregisteredFormatNamesItsProduct() {
        #expect(throws: ReaderError.formatNotIncluded(.cb7)) {
            try ReaderFormats.module(for: .cb7)
        }
        #expect(ReaderError.formatNotIncluded(.cb7).recoverySuggestion?.contains("ChekReaderArchives") == true)
    }

    @Test func registeredFormatResolves() throws {
        ReaderFormats.register(StubModule.self)
        #expect(ReaderFormats.isRegistered(.fb2))
        #expect(try ObjectIdentifier(ReaderFormats.module(for: .fb2)) == ObjectIdentifier(StubModule.self))
    }

    @Test func everyFormatHasAnExtensionAndMediaType() {
        for format in ReaderFormat.all {
            #expect(!format.fileExtensions.isEmpty, "\(format)")
            #expect(!format.mediaTypes.isEmpty, "\(format)")
        }
        #expect(Set(ReaderFormat.all.map(\.id)).count == ReaderFormat.all.count)
    }
}
