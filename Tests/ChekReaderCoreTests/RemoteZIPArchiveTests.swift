import ChekReaderCore
import ChekReaderTestSupport
import Foundation
import Testing

@Suite struct RemoteZIPArchiveTests {
    private func archive(_ files: [(String, String)]) -> Data {
        var zip = ZIPFixture()
        for (name, content) in files {
            zip.add(name, content)
        }
        return zip.data()
    }

    @Test func readsEntriesWithRangeRequests() async throws {
        let big = String(repeating: "chapter text ", count: 20_000)
        let server = RangeServer(archive([("mimetype", "application/epub+zip"), ("a.txt", big), ("b.txt", "second")]))
        let container = try await RemoteZIPArchive.open(server.url, options: server.options(), limits: .default)
        #expect(server.received.count == 1, "the directory comes with the first request")
        #expect(container.paths == ["mimetype", "a.txt", "b.txt"])
        #expect(await container.length(of: "a.txt") == Int64(big.utf8.count))

        #expect(try await container.data(at: "b.txt") == Data("second".utf8))
        #expect(try await container.data(at: "a.txt") == Data(big.utf8))
        #expect(server.received.count == 3, "one request per entry")
        #expect(server.received.allSatisfy { $0.value(forHTTPHeaderField: "Range") != nil })
    }

    @Test func fetchesADirectoryLargerThanTheTail() async throws {
        let files = (0..<1500).map { (String(format: "OEBPS/images/illustration-%04d-with-a-long-name.png", $0), "x") }
        let server = RangeServer(archive(files))
        let container = try await RemoteZIPArchive.open(server.url, options: server.options(), limits: .default)
        #expect(container.paths?.count == 1500)
        #expect(server.received.count == 2)
        #expect(try await container.data(at: "OEBPS/images/illustration-0042-with-a-long-name.png") == Data("x".utf8))
    }

    @Test func downloadsTheWholeFileWhenTheServerIgnoresRanges() async throws {
        let server = RangeServer(archive([("a.txt", "hello")]), supportsRanges: false)
        let container = try await RemoteZIPArchive.open(server.url, options: server.options(), limits: .default)
        #expect(try await container.data(at: "a.txt") == Data("hello".utf8))
        #expect(server.received.count == 1)
    }

    @Test func authorizesEveryRequest() async throws {
        let server = RangeServer(archive([("a.txt", "hello")]))
        let options = server.options { request in
            var request = request
            request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
            return request
        }
        let container = try await RemoteZIPArchive.open(server.url, options: options, limits: .default)
        _ = try await container.data(at: "a.txt")
        #expect(server.received.count == 2)
        #expect(server.received.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token" })
    }

    @Test func reportsServerErrors() async {
        let server = RangeServer(Data(), status: 403)
        await #expect {
            _ = try await RemoteZIPArchive.open(server.url, options: server.options(), limits: .default)
        } throws: { error in
            guard case .network(let reason) = error as? ReaderError else { return false }
            return reason.contains("403")
        }
    }

    @Test func enforcesLimitsOnAWholeDownload() async {
        let server = RangeServer(archive([("a.txt", String(repeating: "a", count: 4096))]), supportsRanges: false)
        var limits = ReaderLimits.default
        limits.maxUncompressedBytes = 1024
        await #expect(throws: ReaderError.limitExceeded(.uncompressedBytes)) {
            _ = try await RemoteZIPArchive.open(server.url, options: server.options(), limits: limits)
        }
    }
}
