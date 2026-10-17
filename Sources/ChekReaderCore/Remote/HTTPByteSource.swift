import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads byte ranges of a file on an HTTP server.
///
/// Every request goes through ``RemoteOptions/authorize`` first, so apps
/// can add credentials and refresh them between requests.
struct HTTPByteSource: Sendable {
    let url: URL
    let options: RemoteOptions
    /// The file's size, from the server's `Content-Range`.
    let count: Int64

    /// What the first request found out.
    enum Opened: Sendable {
        /// The server reads ranges. `tail` holds the file's last bytes.
        case ranges(HTTPByteSource, tail: Data)
        /// The server ignored the range and sent the whole file.
        case whole(Data)
    }

    /// Asks for the last `tailLength` bytes, which also reports the file's
    /// size. A server that ignores ranges sends the whole file instead,
    /// which is accepted up to `maxBytes`.
    static func open(_ url: URL, options: RemoteOptions, tailLength: Int64, maxBytes: Int64) async throws(ReaderError) -> Opened {
        var request = URLRequest(url: url)
        request.setValue("bytes=-\(tailLength)", forHTTPHeaderField: "Range")
        let (data, response) = try await send(request, options: options)
        switch response.statusCode {
        case 206:
            guard let range = response.value(forHTTPHeaderField: "Content-Range").flatMap({ ContentRange($0) }),
                  range.count == Int64(data.count), range.end == range.total
            else {
                throw .network(reason: "\(url.lastPathComponent) came back with a missing or inconsistent Content-Range header.")
            }
            return .ranges(HTTPByteSource(url: url, options: options, count: range.total), tail: data)
        case 200:
            guard Int64(data.count) <= maxBytes else {
                throw .limitExceeded(.uncompressedBytes)
            }
            return .whole(data)
        default:
            throw status(response.statusCode, url: url)
        }
    }

    /// The bytes in `range`, which must be within the file.
    func read(_ range: Range<Int64>) async throws(ReaderError) -> Data {
        guard range.lowerBound >= 0, range.upperBound <= count else {
            throw .malformed(reason: "The archive points past the end of \(url.lastPathComponent). It may be truncated.")
        }
        guard !range.isEmpty else { return Data() }
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        let (data, response) = try await Self.send(request, options: options)
        guard response.statusCode == 206 else {
            throw response.statusCode == 200
                ? .network(reason: "The server stopped honoring range requests for \(url.lastPathComponent).")
                : Self.status(response.statusCode, url: url)
        }
        guard Int64(data.count) == Int64(range.count) else {
            throw .network(reason: "The server sent \(data.count) bytes of \(url.lastPathComponent) where \(range.count) were asked for.")
        }
        return data
    }

    private static func send(_ request: URLRequest, options: RemoteOptions) async throws(ReaderError) -> (Data, HTTPURLResponse) {
        try ReaderError.checkCancellation()
        let url = request.url?.lastPathComponent ?? "the publication"
        let authorized: URLRequest
        do {
            authorized = try await options.authorize(request)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .network(reason: "Authorizing the request for \(url) failed: \(error.localizedDescription)")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await options.load(authorized)
        } catch is CancellationError {
            throw .cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw .cancelled
        } catch {
            throw .network(reason: "Loading \(url) failed: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw .network(reason: "\(url) didn't come back as an HTTP response.")
        }
        return (data, http)
    }

    private static func status(_ code: Int, url: URL) -> ReaderError {
        switch code {
        case 401, 403:
            .network(reason: "The server refused access to \(url.lastPathComponent) (HTTP \(code)). Check the credentials RemoteOptions.authorize adds.")
        case 404:
            .network(reason: "The server has no file at \(url.absoluteString) (HTTP 404).")
        default:
            .network(reason: "The server answered HTTP \(code) for \(url.lastPathComponent).")
        }
    }
}

/// A parsed `Content-Range: bytes start-end/total` header, with `end`
/// exclusive.
struct ContentRange: Equatable, Sendable {
    let start: Int64
    let end: Int64
    let total: Int64

    var count: Int64 { end - start }

    init(start: Int64, end: Int64, total: Int64) {
        self.start = start
        self.end = end
        self.total = total
    }

    init?(_ header: String) {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }
        let value = trimmed.dropFirst(6)
        let parts = value.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let total = Int64(parts[1]) else { return nil }
        let bounds = parts[0].split(separator: "-", maxSplits: 1)
        guard bounds.count == 2, let first = Int64(bounds[0]), let last = Int64(bounds[1]),
              first >= 0, first <= last, last < total
        else { return nil }
        self.init(start: first, end: last + 1, total: total)
    }
}
