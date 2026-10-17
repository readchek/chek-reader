public import Foundation

/// Works out a publication's format from its first bytes and, when the
/// bytes are not conclusive, its file name.
///
/// Content wins over the name, so a renamed file still opens correctly.
/// The sniffer reads at most ``FormatSniffer/prefixLength`` bytes.
public enum FormatSniffer {
    /// How many leading bytes ``format(of:fileName:)`` looks at.
    public static let prefixLength = 512

    public static func format(of prefix: Data, fileName: String? = nil) -> ReaderFormat? {
        let bytes = [UInt8](prefix.prefix(prefixLength))
        let byName = fileName.flatMap(format(forFileName:))

        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            // An EPUB's first ZIP entry is a stored file named "mimetype".
            if storedMimetype(in: bytes) == "application/epub+zip" {
                return .epub
            }
            return byName == .fb2Zip ? .fb2Zip : .cbz
        }
        if bytes.starts(with: Array("%PDF-".utf8)) {
            return .pdf
        }
        if bytes.starts(with: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]) {
            return .cbr
        }
        if bytes.starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
            return .cb7
        }
        if bytes.count >= 262, Array(bytes[257..<262]) == Array("ustar".utf8) {
            return .cbt
        }
        if bytes.count >= 68, Array(bytes[60..<68]) == Array("BOOKMOBI".utf8) {
            // MOBI and AZW3 share the header; KF8 detection happens when the
            // file is parsed, so the name decides between them here.
            return byName == .azw3 ? .azw3 : .mobi
        }
        if String(decoding: bytes, as: UTF8.self).contains("<FictionBook") {
            return .fb2
        }
        return byName
    }

    /// The format a file name suggests, ignoring case.
    public static func format(forFileName fileName: String) -> ReaderFormat? {
        let name = fileName.lowercased()
        // Longest extensions first, so "book.fb2.zip" is not read as ".zip".
        let candidates = ReaderFormat.all.flatMap { format in
            format.fileExtensions.map { (format, "." + $0) }
        }
        .sorted { $0.1.count > $1.1.count }
        return candidates.first { name.hasSuffix($0.1) }?.0
    }

    private static func storedMimetype(in bytes: [UInt8]) -> String? {
        // Local file header: name length at 26, extra length at 28, name at 30.
        guard bytes.count >= 30 else { return nil }
        let nameLength = Int(bytes[26]) | Int(bytes[27]) << 8
        let extraLength = Int(bytes[28]) | Int(bytes[29]) << 8
        let nameEnd = 30 + nameLength
        guard nameEnd <= bytes.count,
              String(bytes: bytes[30..<nameEnd], encoding: .ascii) == "mimetype"
        else { return nil }
        let contentStart = nameEnd + extraLength
        let contentEnd = contentStart + "application/epub+zip".utf8.count
        guard contentEnd <= bytes.count else { return nil }
        return String(bytes: bytes[contentStart..<contentEnd], encoding: .ascii)
    }
}
