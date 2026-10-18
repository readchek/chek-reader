import ChekReaderCore
import Foundation

/// An image embedded in a FictionBook as a `<binary>` element.
struct FB2Binary: Sendable {
    /// The binary's id, which images refer to as `#id`.
    var id: String
    /// Where the decoded image is served, from the publication's root,
    /// such as `images/cover.jpg`.
    var href: String
    var mediaType: String
    var data: Data
}

/// Decodes a FictionBook's `<binary>` elements.
enum FB2Binaries {
    /// The folder decoded binaries go in, from the publication's root.
    static let folder = "images"

    /// Every binary that decodes, in document order. Binaries that don't
    /// decode, or repeat an id, are skipped with a warning.
    ///
    /// - Throws: ``ReaderError/limitExceeded(_:)`` when one binary is larger
    ///   than ``ReaderLimits/maxResourceBytes`` or all of them together are
    ///   larger than ``ReaderLimits/maxUncompressedBytes``.
    static func decode(_ root: MarkupNode, limits: ReaderLimits, warnings: inout [PublicationWarning]) throws(ReaderError) -> [FB2Binary] {
        var binaries: [FB2Binary] = []
        var ids: Set<String> = []
        var names: Set<String> = []
        var total: Int64 = 0
        for element in root.elements(named: "binary") {
            try ReaderError.checkCancellation()
            guard let id = element.attribute("id"), !id.isEmpty else {
                warnings.append(PublicationWarning("A binary has no id, so nothing can show it. It was skipped."))
                continue
            }
            guard !ids.contains(id) else {
                warnings.append(PublicationWarning("More than one binary has the id \"\(id)\". The first one is used."))
                continue
            }
            // Base64 is wrapped across lines, which the decoder skips.
            guard let data = Data(base64Encoded: element.text, options: .ignoreUnknownCharacters), !data.isEmpty else {
                warnings.append(PublicationWarning("The binary \"\(id)\" isn't valid base64. It was skipped."))
                continue
            }
            guard Int64(data.count) <= limits.maxResourceBytes else {
                throw .limitExceeded(.resourceBytes)
            }
            total += Int64(data.count)
            guard total <= limits.maxUncompressedBytes else {
                throw .limitExceeded(.uncompressedBytes)
            }
            ids.insert(id)

            let declared = element.attribute("content-type")?.trimmingCharacters(in: .whitespaces).lowercased()
            let fileExtension = declared.map(Self.fileExtension(for:)) ?? ""
            var base = FB2Path.component(id) ?? "image"
            // Ids such as `cover.jpg` already carry their extension.
            if !fileExtension.isEmpty, base.lowercased().hasSuffix("." + fileExtension) {
                base.removeLast(fileExtension.count + 1)
            }
            let name = FB2Path.unique(base.isEmpty ? "image" : base, extension: fileExtension, in: &names)
            let mediaType = declared.flatMap { $0.isEmpty ? nil : $0 } ?? MediaType.forPath(name)
            binaries.append(FB2Binary(id: id, href: "\(folder)/\(name)", mediaType: mediaType, data: data))
        }
        return binaries
    }

    /// The file extension for an image media type, or an empty string when
    /// it isn't one the reader recognizes.
    private static func fileExtension(for mediaType: String) -> String {
        switch mediaType {
        case "image/jpeg", "image/jpg", "image/pjpeg": "jpg"
        case "image/png": "png"
        case "image/gif": "gif"
        case "image/webp": "webp"
        case "image/avif": "avif"
        case "image/svg+xml": "svg"
        default: ""
        }
    }
}
