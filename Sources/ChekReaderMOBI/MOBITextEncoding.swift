/// The two text encodings MOBI headers declare.
enum MOBITextEncoding: Sendable, Equatable {
    /// Windows-1252, MOBI's original encoding.
    case cp1252
    /// UTF-8, which every KF8 book and most recent MOBI books use.
    case utf8

    /// The name to declare in markup.
    var charsetName: String {
        switch self {
        case .cp1252: "windows-1252"
        case .utf8: "utf-8"
        }
    }

    /// Decodes `bytes`, replacing anything invalid with U+FFFD.
    func decode(_ bytes: some Collection<UInt8>) -> String {
        switch self {
        case .utf8:
            return String(decoding: bytes, as: UTF8.self)
        case .cp1252:
            var result = String.UnicodeScalarView()
            for byte in bytes {
                result.append(Self.cp1252Scalar(byte))
            }
            return String(result)
        }
    }

    /// Windows-1252 matches Latin-1 except in 0x80...0x9F, where it has
    /// typographic punctuation and a few letters instead of C1 controls.
    /// The five bytes it leaves undefined decode to U+FFFD.
    static func cp1252Scalar(_ byte: UInt8) -> Unicode.Scalar {
        guard byte >= 0x80, byte <= 0x9F else {
            return Unicode.Scalar(byte)
        }
        let value = cp1252High[Int(byte - 0x80)]
        return Unicode.Scalar(value) ?? "\u{FFFD}"
    }

    private static let cp1252High: [UInt32] = [
        0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
        0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
    ]
}
