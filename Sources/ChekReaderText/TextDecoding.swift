import Foundation

/// Turns a text file's bytes into a string, whatever its encoding.
enum TextDecoding {
    /// The text in `data`: by its byte order mark when it has one, else as
    /// UTF-8, else as Windows-1252, the usual encoding of older text files.
    /// Line endings become `\n`.
    static func decode(_ data: Data) -> String {
        var text: String?
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            text = String(decoding: data.dropFirst(3), as: UTF8.self)
        } else if data.starts(with: [0xFF, 0xFE]) {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if text == nil {
            text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(decoding: data, as: UTF8.self)
        }
        return (text ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// A title made from a file name: without its extension, and with
    /// underscores as spaces.
    static func title(fromFileName fileName: String?) -> String? {
        guard var name = fileName else { return nil }
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            name = String(name[..<dot])
        }
        let title = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}
