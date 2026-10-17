/// The image formats MOBI books store, recognized by their magic bytes,
/// since image records carry no type of their own.
enum ImageType: Sendable, Equatable {
    case jpeg
    case png
    case gif
    case bmp
    case webp

    init?(sniffing bytes: [UInt8]) {
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            self = .jpeg
        } else if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            self = .png
        } else if bytes.hasSignature("GIF87a") || bytes.hasSignature("GIF89a") {
            self = .gif
        } else if bytes.hasSignature("BM"), bytes.count >= 14 {
            self = .bmp
        } else if bytes.hasSignature("RIFF"), bytes.count >= 12, bytes[8..<12].elementsEqual("WEBP".utf8) {
            self = .webp
        } else {
            return nil
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .gif: "gif"
        case .bmp: "bmp"
        case .webp: "webp"
        }
    }

    var mediaType: String {
        switch self {
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        case .gif: "image/gif"
        case .bmp: "image/bmp"
        case .webp: "image/webp"
        }
    }
}
