import ChekReaderCore
import Foundation

/// Reads the pages of a ``PageSource``, served at `pages/1`, `pages/2` and so on.
struct PageSourceContainer: PublicationContainer {
    let source: any PageSource
    let pageCount: Int
    let limits: ReaderLimits

    static func href(forPage index: Int) -> String {
        "pages/\(index + 1)"
    }

    var paths: Set<String>? {
        Set((0..<pageCount).map(Self.href(forPage:)))
    }

    func data(at path: String) async throws(ReaderError) -> Data {
        guard path.hasPrefix("pages/"), let number = Int(path.dropFirst(6)), (1...pageCount).contains(number) else {
            throw .malformed(reason: "The page source has no page at \(path).")
        }
        let data: Data
        do {
            data = try await source.page(at: number - 1)
        } catch let error as ReaderError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .network(reason: "The page source couldn't supply page \(number): \(error.localizedDescription)")
        }
        guard Int64(data.count) <= limits.maxResourceBytes else {
            throw .limitExceeded(.resourceBytes)
        }
        return data
    }
}
