import Foundation

/// Resources held in memory, for formats whose resources are generated
/// while opening, such as a PDF's single file or the documents built from
/// plain text.
package struct MemoryContainer: PublicationContainer {
    private let resources: [String: Data]
    private let positionCounts: [String: Int]

    /// - Parameter positionCounts: How many positions a resource has, for
    ///   resources that know better than their byte size, such as a PDF's
    ///   pages.
    package init(_ resources: [String: Data], positionCounts: [String: Int] = [:]) {
        self.resources = resources
        self.positionCounts = positionCounts
    }

    package var paths: Set<String>? { Set(resources.keys) }

    package func data(at path: String) async throws(ReaderError) -> Data {
        guard let data = resources[path] else {
            throw .malformed(reason: "The publication has no resource named \(path).")
        }
        return data
    }

    package func length(of path: String) async -> Int64? {
        resources[path].map { Int64($0.count) }
    }

    package func positionCount(of path: String) async -> Int? {
        positionCounts[path]
    }
}
