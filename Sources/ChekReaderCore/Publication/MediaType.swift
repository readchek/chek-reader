import Foundation

/// Media types for resources a publication doesn't label.
package enum MediaType {
    /// The media type a path's extension suggests.
    package static func forPath(_ path: String) -> String {
        let fileExtension = path.split(separator: ".").last.map { $0.lowercased() } ?? ""
        return switch fileExtension {
        case "xhtml", "xht": "application/xhtml+xml"
        case "html", "htm": "text/html"
        case "css": "text/css"
        case "js": "text/javascript"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "avif": "image/avif"
        case "heic", "heif": "image/heic"
        case "jxl": "image/jxl"
        case "bmp": "image/bmp"
        case "tif", "tiff": "image/tiff"
        case "otf": "font/otf"
        case "ttf": "font/ttf"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        case "mp3": "audio/mpeg"
        case "m4a", "mp4a": "audio/mp4"
        case "mp4", "m4v": "video/mp4"
        case "smil": "application/smil+xml"
        default: "application/octet-stream"
        }
    }

    /// Whether `mediaType` is HTML or XHTML, ignoring parameters.
    package static func isHTML(_ mediaType: String) -> Bool {
        let type = mediaType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        return type == "application/xhtml+xml" || type == "text/html"
    }
}
