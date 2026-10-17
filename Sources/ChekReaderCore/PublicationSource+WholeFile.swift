import Foundation

extension PublicationSource {
    /// The href a ``ResourceProvider`` is asked for when a format keeps the
    /// whole publication in one file, such as PDF, plain text or FB2.
    public static let wholePublicationHref = ""

    /// The publication's whole file, for formats that keep everything in
    /// one file. Files are memory-mapped, so only the parts read are loaded.
    ///
    /// - Throws: ``ReaderError/limitExceeded(_:)`` when the file is larger
    ///   than ``ReaderLimits/maxResourceBytes``, and
    ///   ``ReaderError/unsupportedFormat(fileName:)`` for page sources.
    package func wholeFile(limits: ReaderLimits) async throws(ReaderError) -> Data {
        let data: Data
        switch self {
        case .file(let url):
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw .malformed(reason: "\(url.lastPathComponent) could not be read. Check that the file exists and the app can access it.")
            }
        case .data(let bytes, _):
            data = bytes
        case .remote(let url, let options):
            data = try await HTTPByteSource.download(url, options: options, maxBytes: limits.maxResourceBytes)
        case .provider(let provider):
            data = try await ProviderContainer(provider: provider, limits: limits).data(at: Self.wholePublicationHref)
        case .pages:
            throw .unsupportedFormat(fileName: nil)
        }
        guard Int64(data.count) <= limits.maxResourceBytes else {
            throw .limitExceeded(.resourceBytes)
        }
        return data
    }
}
