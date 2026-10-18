/// A forgiving scanner for the HTML and XHTML stored in MOBI and KF8 text.
///
/// The text is rewritten as bytes rather than parsed into a tree: MOBI 6
/// markup is rarely well-formed, and KF8 positions are byte offsets into
/// the markup as stored, so the bytes must stay as they are except where a
/// tag is deliberately changed. Only ASCII matters to the scanner, so it
/// works the same on Windows-1252 and UTF-8 text.
enum Markup {
    /// A tag, comment or other markup construct in the text.
    struct Tag: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case start
            case end
            /// A comment, doctype, CDATA section or processing instruction.
            case other
        }

        /// From the `<` to just after the `>`.
        let range: Range<Int>
        let kind: Kind
        /// The lowercased element name, such as `img` or `mbp:pagebreak`.
        let name: String
        /// Whether a start tag ends with `/>`.
        let isSelfClosing: Bool
    }

    /// An attribute in a start tag.
    struct Attribute: Sendable, Equatable {
        /// The lowercased name.
        let name: String
        /// The value as written, without quotes and with entities left alone.
        let value: String?
    }

    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")

    /// The tag that starts at `offset`, which must be a `<`. Returns `nil`
    /// when the `<` doesn't start a tag, as in `a < b`, or the tag never ends.
    static func tag(at offset: Int, in bytes: [UInt8]) -> Tag? {
        guard offset >= 0, offset + 1 < bytes.count, bytes[offset] == lessThan else { return nil }
        let next = bytes[offset + 1]
        if next == UInt8(ascii: "!") || next == UInt8(ascii: "?") {
            let terminator: [UInt8]
            if bytes[offset...].starts(with: "<!--".utf8) {
                terminator = Array("-->".utf8)
            } else if bytes[offset...].starts(with: "<![CDATA[".utf8) {
                terminator = Array("]]>".utf8)
            } else if next == UInt8(ascii: "?") {
                terminator = Array("?>".utf8)
            } else {
                terminator = [greaterThan]
            }
            guard let end = find(terminator, in: bytes, from: offset + 2) else { return nil }
            return Tag(range: offset..<end + terminator.count, kind: .other, name: "", isSelfClosing: false)
        }
        let isEnd = next == UInt8(ascii: "/")
        let nameStart = offset + (isEnd ? 2 : 1)
        guard nameStart < bytes.count, isNameStart(bytes[nameStart]) else { return nil }
        var position = nameStart
        while position < bytes.count, isNameCharacter(bytes[position]) {
            position += 1
        }
        let name = String(decoding: bytes[nameStart..<position], as: UTF8.self).lowercased()
        // Find the closing `>`, skipping any inside quoted attribute values.
        var quote: UInt8?
        while position < bytes.count {
            let byte = bytes[position]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == greaterThan {
                let isSelfClosing = !isEnd && position > nameStart && bytes[position - 1] == UInt8(ascii: "/")
                return Tag(range: offset..<position + 1, kind: isEnd ? .end : .start, name: name, isSelfClosing: isSelfClosing)
            } else if byte == lessThan {
                // A new tag before this one closes: this one is broken text.
                return nil
            }
            position += 1
        }
        return nil
    }

    /// Every tag in `bytes`, in order. Text that only looks like a tag is skipped.
    static func tags(in bytes: [UInt8]) -> [Tag] {
        var tags: [Tag] = []
        var position = 0
        while let start = firstIndex(of: lessThan, in: bytes, from: position) {
            if let tag = tag(at: start, in: bytes) {
                tags.append(tag)
                position = tag.range.upperBound
            } else {
                position = start + 1
            }
        }
        return tags
    }

    /// The attributes of a start tag.
    static func attributes(of tag: Tag, in bytes: [UInt8]) -> [Attribute] {
        guard tag.kind == .start else { return [] }
        var attributes: [Attribute] = []
        var position = tag.range.lowerBound + 1
        let end = tag.range.upperBound - 1
        // Skip the element name.
        while position < end, isNameCharacter(bytes[position]) {
            position += 1
        }
        while position < end {
            let byte = bytes[position]
            if isSpace(byte) || byte == UInt8(ascii: "/") {
                position += 1
                continue
            }
            let nameStart = position
            while position < end, !isSpace(bytes[position]), bytes[position] != UInt8(ascii: "="),
                  bytes[position] != UInt8(ascii: "/") {
                position += 1
            }
            guard position > nameStart else {
                // A stray `=` with no name before it: skip it.
                position += 1
                continue
            }
            let name = String(decoding: bytes[nameStart..<position], as: UTF8.self).lowercased()
            while position < end, isSpace(bytes[position]) {
                position += 1
            }
            guard position < end, bytes[position] == UInt8(ascii: "=") else {
                attributes.append(Attribute(name: name, value: nil))
                continue
            }
            position += 1
            while position < end, isSpace(bytes[position]) {
                position += 1
            }
            var valueStart = position
            var valueEnd = position
            if position < end, bytes[position] == UInt8(ascii: "\"") || bytes[position] == UInt8(ascii: "'") {
                let quote = bytes[position]
                valueStart = position + 1
                valueEnd = valueStart
                while valueEnd < end, bytes[valueEnd] != quote {
                    valueEnd += 1
                }
                position = min(end, valueEnd + 1)
            } else {
                while valueEnd < end, !isSpace(bytes[valueEnd]), bytes[valueEnd] != greaterThan {
                    valueEnd += 1
                }
                // `<a filepos=12/>` ends with the self-closing slash, not the value.
                if valueEnd == end, valueEnd > valueStart, tag.isSelfClosing {
                    valueEnd -= 1
                }
                position = valueEnd
            }
            attributes.append(Attribute(name: name, value: String(decoding: bytes[valueStart..<valueEnd], as: UTF8.self)))
        }
        return attributes
    }

    /// A start tag written from its parts, with values in double quotes.
    static func startTag(_ name: String, _ attributes: [Attribute], selfClosing: Bool) -> [UInt8] {
        var text = "<" + name
        for attribute in attributes {
            text += " " + attribute.name
            if let value = attribute.value {
                text += "=\"" + value.replacing("\"", with: "&quot;") + "\""
            }
        }
        text += selfClosing ? "/>" : ">"
        return Array(text.utf8)
    }

    /// The index of the first `byte` at or after `start`.
    static func firstIndex(of byte: UInt8, in bytes: [UInt8], from start: Int) -> Int? {
        guard start < bytes.count else { return nil }
        return bytes[max(0, start)...].firstIndex(of: byte)
    }

    /// The index of the first occurrence of `needle` at or after `start`.
    static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard let first = needle.first, !needle.isEmpty else { return nil }
        var position = max(0, start)
        while let candidate = firstIndex(of: first, in: bytes, from: position) {
            if bytes[candidate...].starts(with: needle) {
                return candidate
            }
            position = candidate + 1
        }
        return nil
    }

    /// Like ``find(_:in:from:)``, ignoring ASCII case. `needle` must be lowercase.
    static func findIgnoringCase(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, needle.count <= bytes.count else { return nil }
        var position = max(0, start)
        while position <= bytes.count - needle.count {
            var matches = true
            for index in 0..<needle.count where lowercase(bytes[position + index]) != needle[index] {
                matches = false
                break
            }
            if matches {
                return position
            }
            position += 1
        }
        return nil
    }

    static func lowercase(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 32 : byte
    }

    static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }

    private static func isNameStart(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
    }

    private static func isNameCharacter(_ byte: UInt8) -> Bool {
        isNameStart(byte) || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))
            || byte == UInt8(ascii: ":") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ".")
    }

    /// Whether `bytes` holds anything but whitespace.
    static func hasContent(_ bytes: [UInt8]) -> Bool {
        bytes.contains { !isSpace($0) }
    }
}
