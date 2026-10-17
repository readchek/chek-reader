import ChekReaderCore
import ChekReaderEPUB
import ChekReaderNavigator
import Foundation
import Testing

@MainActor
@Suite struct ReaderControllerTests {
    @Test func unregisteredFormatFails() async {
        let controller = ReaderController()
        await #expect(throws: ReaderError.formatNotIncluded(.cb7)) {
            try await controller.open(.data(Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])))
        }
        #expect(controller.state == .failed(.formatNotIncluded(.cb7)))
        #expect(controller.format == .cb7)
    }

    @Test func unknownContentFails() async {
        let controller = ReaderController()
        await #expect(throws: ReaderError.unsupportedFormat(fileName: "a.bin")) {
            try await controller.open(.data(Data("hello".utf8), fileName: "a.bin"))
        }
    }

    @Test func registeredFormatReachesItsModule() async {
        ReaderFormats.register(EPUBModule.self)
        let controller = ReaderController()
        await #expect(throws: ReaderError.notYetImplemented(.epub)) {
            try await controller.open(.remote(URL(string: "https://example.com/book.epub")!))
        }
    }

    @Test func closeEndsTheSession() async {
        let controller = ReaderController()
        try? await controller.open(.data(Data("%PDF-1.7".utf8)))
        await controller.close()
        #expect(controller.state == .closed)
    }
}
