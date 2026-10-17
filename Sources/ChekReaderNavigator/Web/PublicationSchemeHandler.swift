#if canImport(WebKit) && canImport(SwiftUI)
import ChekReaderCore
import Foundation
import WebKit

/// Answers the web view's requests for publication resources.
///
/// WebKit cancels the stream when a page goes away, which cancels the read,
/// so no archive work outlives the page that asked for it.
struct PublicationSchemeHandler: URLSchemeHandler {
    let server: PublicationServer

    func reply(for request: URLRequest) -> AsyncThrowingStream<URLSchemeTaskResult, any Error> {
        let server = server
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let url = request.url else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                let served = await server.response(for: url)
                guard !Task.isCancelled else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                guard let response = HTTPURLResponse(
                    url: url,
                    statusCode: served.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: served.headers
                ) else {
                    continuation.finish(throwing: URLError(.cannotParseResponse))
                    return
                }
                continuation.yield(.response(response))
                if !served.body.isEmpty {
                    continuation.yield(.data(served.body))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
