import Foundation

/// Where a parsed publication reads its resources from.
package protocol PublicationContainer: Sendable {
    /// The path of every resource, when the container can list them.
    var paths: Set<String>? { get }
    /// The bytes of the resource at `path`, relative to the publication's root.
    func data(at path: String) async throws(ReaderError) -> Data
    /// The size of the resource at `path` in bytes, when the container
    /// knows it without reading the resource.
    func length(of path: String) async -> Int64?
    /// How many positions the resource at `path` has, when the container
    /// knows better than its size, such as the pages of a PDF.
    func positionCount(of path: String) async -> Int?
}

extension PublicationContainer {
    /// Whether the container has `path`. Containers that can't list their
    /// contents are assumed to have everything.
    package func contains(_ path: String) -> Bool {
        paths?.contains(path) ?? true
    }

    package func length(of path: String) async -> Int64? {
        nil
    }

    package func positionCount(of path: String) async -> Int? {
        nil
    }
}

/// Reads resources from an app's ``ResourceProvider``.
package struct ProviderContainer: PublicationContainer {
    package let provider: any ResourceProvider
    package let limits: ReaderLimits

    package init(provider: any ResourceProvider, limits: ReaderLimits) {
        self.provider = provider
        self.limits = limits
    }

    package var paths: Set<String>? { nil }

    package func data(at path: String) async throws(ReaderError) -> Data {
        let data: Data
        do {
            data = try await provider.data(at: path)
        } catch let error as ReaderError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .malformed(reason: "The resource provider couldn't supply \(path): \(error.localizedDescription)")
        }
        guard Int64(data.count) <= limits.maxResourceBytes else {
            throw .limitExceeded(.resourceBytes)
        }
        return data
    }
}
