import ChekReaderCore
import ChekReaderEPUB
import ChekReaderNavigator
import ChekReaderTestSupport
import Foundation
import Testing

@Suite struct PublicationServerTests {
    private func server(allowsScripts: Bool = false) async throws -> PublicationServer {
        let book = EPUBFixture.book(EPUBFixture.epub3)
        let publication = try await EPUBModule.open(.data(book), format: .epub, limits: .default)
        return PublicationServer(publication: publication, allowsScripts: allowsScripts)
    }

    @Test func mapsHrefsToURLsAndBack() {
        let url = PublicationServer.url(for: "OEBPS/Text/chapter 1.xhtml#part2")
        #expect(url.scheme == "chek-reader")
        #expect(url.absoluteString == "chek-reader://publication/OEBPS/Text/chapter%201.xhtml#part2")
        #expect(PublicationServer.href(for: url) == "OEBPS/Text/chapter 1.xhtml#part2")
        #expect(PublicationServer.href(for: URL(string: "https://example.com/a.xhtml")!) == nil)
    }

    @Test func servesDocumentsWithAContentSecurityPolicy() async throws {
        let server = try await server()
        let response = await server.response(for: PublicationServer.url(for: "OEBPS/Text/chapter2.xhtml"))
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "application/xhtml+xml")
        let policy = try #require(response.headers["Content-Security-Policy"])
        #expect(policy.contains("script-src 'none'"))
        #expect(policy.contains("connect-src 'none'"))
        #expect(policy.contains("default-src chek-reader:"))

        let html = String(decoding: response.body, as: UTF8.self)
        #expect(html.contains(#"<head><meta http-equiv="Content-Security-Policy""#))
        #expect(html.contains("<h1>Chapter Two</h1>"))
        #expect(response.headers["Content-Length"] == String(response.body.count))
    }

    @Test func allowsScriptsOnlyWhenAsked() async throws {
        let server = try await server(allowsScripts: true)
        #expect(server.contentSecurityPolicy.contains("script-src chek-reader: 'unsafe-inline'"))
    }

    @Test func servesOtherResourcesUnchanged() async throws {
        let server = try await server()
        let response = await server.response(for: PublicationServer.url(for: "OEBPS/styles/book.css"))
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "text/css")
        #expect(response.headers["Content-Security-Policy"] == nil)
        #expect(response.body == Data("body { margin: 0 }".utf8))
    }

    @Test func refusesUnknownResourcesAndOtherHosts() async throws {
        let server = try await server()
        #expect(await server.response(for: PublicationServer.url(for: "OEBPS/missing.xhtml")).statusCode == 404)
        #expect(await server.response(for: URL(string: "chek-reader://elsewhere/OEBPS/nav.xhtml")!).statusCode == 404)
        #expect(await server.response(for: URL(string: "https://example.com/OEBPS/nav.xhtml")!).statusCode == 404)
    }
}
