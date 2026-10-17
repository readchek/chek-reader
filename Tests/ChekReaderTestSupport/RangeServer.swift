import ChekReaderCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization

/// Serves one file over pretend HTTP, honoring `Range` headers the way a
/// real server does, and records every request it gets.
package final class RangeServer: Sendable {
    package let url: URL
    private let file: Data
    private let supportsRanges: Bool
    private let status: Int
    private let requests = Mutex<[URLRequest]>([])

    package init(_ file: Data, url: URL = URL(string: "https://books.example/library/book.epub")!, supportsRanges: Bool = true, status: Int = 200) {
        self.file = file
        self.url = url
        self.supportsRanges = supportsRanges
        self.status = status
    }

    /// Every request served so far.
    package var received: [URLRequest] {
        requests.withLock { $0 }
    }

    /// Options that send requests here instead of the network.
    package func options(authorize: @escaping @Sendable (URLRequest) async throws -> URLRequest = { $0 }) -> RemoteOptions {
        RemoteOptions(authorize: authorize) { [self] request in
            try self.respond(to: request)
        }
    }

    private func respond(to request: URLRequest) throws -> (Data, URLResponse) {
        requests.withLock { $0.append(request) }
        let url = try require(request.url)
        guard status == 200 else {
            return (Data(), response(url, status: status, headers: [:]))
        }
        guard supportsRanges, let header = request.value(forHTTPHeaderField: "Range"), let range = range(header) else {
            return (file, response(url, status: 200, headers: ["Content-Length": "\(file.count)"]))
        }
        let body = file.subdata(in: range)
        return (body, response(url, status: 206, headers: [
            "Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(file.count)",
            "Content-Length": "\(body.count)",
        ]))
    }

    /// The bytes `bytes=a-b` or `bytes=-n` asks for, clamped to the file.
    private func range(_ header: String) -> Range<Int>? {
        guard header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst(6)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = Int(parts[1]) {
            return max(0, file.count - suffix)..<file.count
        }
        guard let start = Int(parts[0]), let end = Int(parts[1]), start <= end, start < file.count else { return nil }
        return start..<min(end + 1, file.count)
    }

    private func response(_ url: URL, status: Int, headers: [String: String]) -> URLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}

private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw URLError(.badURL) }
    return value
}
