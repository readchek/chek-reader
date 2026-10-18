/// A `kindle:` URL in KF8 markup or CSS.
enum KindleURL: Sendable, Equatable, Hashable {
    /// `kindle:embed:XXXX?mime=…`: resource XXXX, base 32 and 1-based from
    /// the first image index.
    case embed(Int)
    /// `kindle:flow:XXXX?mime=…`: flow XXXX of the text, base 32.
    case flow(Int)
    /// `kindle:pos:fid:FFFF:off:OOOOOOOOOO`: offset O into fragment F, both base 32.
    case position(fragment: Int, offset: Int)

    static let scheme = Array("kindle:".utf8)

    init?(_ text: String) {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("kindle:embed:") {
            guard let number = Self.base32(Self.digits(after: "kindle:embed:", in: text)) else { return nil }
            self = .embed(number)
        } else if lowercased.hasPrefix("kindle:flow:") {
            guard let number = Self.base32(Self.digits(after: "kindle:flow:", in: text)) else { return nil }
            self = .flow(number)
        } else if lowercased.hasPrefix("kindle:pos:fid:") {
            let fields = text.dropFirst("kindle:pos:fid:".count).split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 3, fields[1].lowercased() == "off",
                  let fragment = Self.base32(String(fields[0])),
                  let offset = Self.base32(String(fields[2].prefix { $0 != "?" }))
            else { return nil }
            self = .position(fragment: fragment, offset: offset)
        } else {
            return nil
        }
    }

    /// The part of `text` after `prefix`, up to any query.
    private static func digits(after prefix: String, in text: String) -> String {
        String(text.dropFirst(prefix.count).prefix { $0 != "?" && $0 != "#" })
    }

    /// Decodes Kindle's base 32, digits `0-9` then `A-V`. At most twelve
    /// digits are accepted, so the value always fits.
    static func base32(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 12 else { return nil }
        var value = 0
        for character in text.uppercased().unicodeScalars {
            let digit: UInt32
            switch character.value {
            case 0x30...0x39: digit = character.value - 0x30
            case 0x41...0x56: digit = character.value - 0x41 + 10
            default: return nil
            }
            value = value * 32 + Int(digit)
        }
        return value
    }

    /// Replaces every `kindle:` URL in `bytes` with what `resolve` returns
    /// for it. URLs it returns `nil` for, or that don't parse, are passed
    /// to `unresolved` and left as they are.
    static func rewrite(
        _ bytes: [UInt8],
        resolve: (KindleURL) -> String?,
        unresolved: (String) -> Void
    ) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var cursor = 0
        while let start = Markup.find(scheme, in: bytes, from: cursor) {
            var end = start + scheme.count
            while end < bytes.count, !isTerminator(bytes[end]) {
                end += 1
            }
            output += bytes[cursor..<start]
            let text = String(decoding: bytes[start..<end], as: UTF8.self)
            if let url = KindleURL(text), let replacement = resolve(url) {
                output += Array(replacement.utf8)
            } else {
                unresolved(text)
                output += bytes[start..<end]
            }
            cursor = end
        }
        output += bytes[cursor...]
        return output
    }

    /// Characters that end a URL in an attribute or CSS `url()`.
    private static func isTerminator(_ byte: UInt8) -> Bool {
        Markup.isSpace(byte) || byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") || byte == UInt8(ascii: ")")
            || byte == Markup.lessThan || byte == Markup.greaterThan
    }
}
