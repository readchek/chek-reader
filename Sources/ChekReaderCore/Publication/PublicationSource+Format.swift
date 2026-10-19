import Foundation

extension FormatSniffer {
    /// Detects the format of a source, reading at most ``prefixLength``
    /// bytes of a file. Remote sources are detected by their URL's file name.
    package static func format(of source: PublicationSource) async throws(ReaderError) -> ReaderFormat? {
        switch source {
        case .file(let url):
            let prefix: Data
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                prefix = try handle.read(upToCount: prefixLength) ?? Data()
            } catch {
                throw .malformed(reason: "\(url.lastPathComponent) could not be read. Check that the file exists and the app can access it.")
            }
            return format(of: prefix, fileName: url.lastPathComponent)
        case .data(let data, let fileName):
            return format(of: data, fileName: fileName)
        case .remote(let url, let options):
            // A name settles it without a request. Server APIs often serve
            // files at addresses with no extension, such as
            // `/publications/12/file`, so then the first bytes decide.
            if let byName = format(forFileName: url.lastPathComponent) {
                return byName
            }
            let prefix = try await HTTPByteSource.prefix(of: url, options: options, length: prefixLength)
            return format(of: prefix, fileName: url.lastPathComponent)
        case .provider(let provider):
            return provider.format
        case .pages:
            return .cbz
        }
    }
}

extension PublicationSource {
    /// The source's file name, when it has one.
    package var fileName: String? {
        switch self {
        case .file(let url), .remote(let url, _): url.lastPathComponent
        case .data(_, let fileName): fileName
        case .provider, .pages: nil
        }
    }
}
