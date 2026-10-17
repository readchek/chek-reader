@testable import ChekReaderNavigator
import Foundation
import Testing

@Suite struct ReaderScriptTests {
    @Test func bundlesTheCompiledScript() {
        #expect(ReaderScript.source.contains("globalThis"))
        #expect(ReaderScript.source.contains("chekReader"))
        #expect(ReaderScript.source.contains(ReaderScript.messageHandler))
    }

    @Test func readsPageStateReplies() throws {
        let state = try #require(ScriptPageState(["page": 2, "pageCount": 5, "progression": 0.4, "generation": 7] as [String: Any]))
        #expect(state.page == 2)
        #expect(state.pageCount == 5)
        #expect(state.generation == 7)

        let fromDoubles = try #require(ScriptPageState(["page": 1.0, "pageCount": 3.0] as [String: Any]))
        #expect(fromDoubles.page == 1)
        #expect(fromDoubles.generation == 0)
    }

    @Test func rejectsRepliesWithoutPages() {
        #expect(ScriptPageState(nil) == nil)
        #expect(ScriptPageState(["page": 0, "pageCount": 0] as [String: Any]) == nil)
        #expect(ScriptPageState(["page": "first", "pageCount": 2] as [String: Any]) == nil)
        #expect(ScriptPageState(["page": Double.infinity, "pageCount": 2] as [String: Any]) == nil)
    }

    @Test func clampsAPageOutsideTheResource() throws {
        let state = try #require(ScriptPageState(["page": 9, "pageCount": 3] as [String: Any]))
        #expect(state.page == 2)
    }
}
