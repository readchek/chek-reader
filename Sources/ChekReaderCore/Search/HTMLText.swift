/// The text a browser shows for an HTML or XHTML document, laid out the way
/// the reader script indexes it, so a slice of it is an anchor the script's
/// `goToText` finds again.
///
/// The script joins the body's text nodes end to end, leaving out `script`
/// and `style`, and collapses every run of whitespace to one space. This
/// does the same from the markup, without a browser, so search can run on
/// any platform and before a resource is shown. Text in adjacent elements
/// with no whitespace between them runs together, as it does for the
/// script, so a slice of this text is always a slice of the script's.
package enum HTMLText {
    /// The body's text with whitespace collapsed, like the script's index,
    /// without the space either end of the body usually has.
    package static func flatten(_ html: String) -> String {
        var scanner = Scanner(html.unicodeScalars)
        var text = String.UnicodeScalarView()
        /// Whether the last scalar written was the one space a run becomes.
        var spaced = false
        func write(_ scalar: Unicode.Scalar) {
            if isWhitespace(scalar) {
                if !spaced {
                    text.append(" ")
                    spaced = true
                }
            } else {
                text.append(scalar)
                spaced = false
            }
        }

        var inHead = false
        var sawBody = false
        while let scalar = scanner.next() {
            switch scalar {
            case "<":
                guard let tag = scanner.tag() else {
                    // A stray `<` is text, as a browser treats it.
                    if !inHead { write("<") }
                    continue
                }
                switch tag {
                case .comment, .declaration:
                    continue
                case .cdata(let content):
                    if !inHead {
                        for scalar in content { write(scalar) }
                    }
                case .open(let name):
                    switch name {
                    case "head":
                        inHead = true
                    case "body":
                        // Only the body's text is indexed; what came before,
                        // such as whitespace between `head` and `body`, isn't.
                        if !sawBody {
                            sawBody = true
                            text.removeAll(keepingCapacity: true)
                            spaced = false
                        }
                    case "script", "style":
                        scanner.skipElement(named: name)
                    default:
                        break
                    }
                case .close(let name):
                    if name == "head" { inHead = false }
                }
            case "&":
                let decoded = scanner.entity() ?? "&"
                if !inHead {
                    for scalar in decoded.unicodeScalars { write(scalar) }
                }
            default:
                if !inHead { write(scalar) }
            }
        }
        if text.first == " " { text.removeFirst() }
        if text.last == " " { text.removeLast() }
        return String(text)
    }

    /// Whether `scalar` matches JavaScript's `\s`, which the script collapses.
    package static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case " ", "\t", "\n", "\u{B}", "\u{C}", "\r", "\u{A0}", "\u{1680}", "\u{2000}"..."\u{200A}",
             "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}", "\u{FEFF}":
            true
        default:
            false
        }
    }

    private enum Tag {
        case open(String)
        case close(String)
        case comment
        case declaration
        case cdata(String.UnicodeScalarView.SubSequence)
    }

    /// Reads markup scalar by scalar, after a `<` or `&` was seen.
    private struct Scanner {
        private let scalars: String.UnicodeScalarView
        private var index: String.UnicodeScalarView.Index

        init(_ scalars: String.UnicodeScalarView) {
            self.scalars = scalars
            index = scalars.startIndex
        }

        mutating func next() -> Unicode.Scalar? {
            guard index < scalars.endIndex else { return nil }
            defer { index = scalars.index(after: index) }
            return scalars[index]
        }

        private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
            guard let at = scalars.index(index, offsetBy: offset, limitedBy: scalars.endIndex), at < scalars.endIndex else {
                return nil
            }
            return scalars[at]
        }

        private func starts(with prefix: String) -> Bool {
            var at = index
            for scalar in prefix.unicodeScalars {
                guard at < scalars.endIndex, scalars[at] == scalar else { return false }
                at = scalars.index(after: at)
            }
            return true
        }

        /// Moves past `marker`, or to the end when it never comes, and
        /// returns what was skipped.
        private mutating func skip(past marker: String) -> String.UnicodeScalarView.SubSequence {
            let start = index
            while index < scalars.endIndex {
                if starts(with: marker) {
                    let content = scalars[start..<index]
                    index = scalars.index(index, offsetBy: marker.unicodeScalars.count)
                    return content
                }
                index = scalars.index(after: index)
            }
            return scalars[start..<index]
        }

        /// The tag that starts at the current position, just after its `<`,
        /// with the position moved past it. `nil` when the `<` isn't markup.
        mutating func tag() -> Tag? {
            if starts(with: "!--") {
                _ = skip(past: "-->")
                return .comment
            }
            if starts(with: "![CDATA[") {
                index = scalars.index(index, offsetBy: 8)
                return .cdata(skip(past: "]]>"))
            }
            if peek() == "!" || peek() == "?" {
                _ = skip(past: ">")
                return .declaration
            }
            var closing = false
            if peek() == "/" {
                closing = true
                index = scalars.index(after: index)
            }
            var name = ""
            while let scalar = peek(), isNameScalar(scalar) {
                name.unicodeScalars.append(scalar)
                index = scalars.index(after: index)
            }
            guard !name.isEmpty else { return nil }
            // Attribute values may hold `>`, so quotes are tracked to the tag's end.
            var quote: Unicode.Scalar?
            while let scalar = next() {
                if let open = quote {
                    if scalar == open { quote = nil }
                } else if scalar == "\"" || scalar == "'" {
                    quote = scalar
                } else if scalar == ">" {
                    break
                }
            }
            let lowered = name.lowercased()
            return closing ? .close(lowered) : .open(lowered)
        }

        /// Moves past the closing tag of the element just opened, whose
        /// content isn't text, such as a script.
        mutating func skipElement(named name: String) {
            while index < scalars.endIndex {
                if peek() == "<", peek(1) == "/" {
                    let start = index
                    index = scalars.index(index, offsetBy: 2)
                    var found = ""
                    while let scalar = peek(), isNameScalar(scalar) {
                        found.unicodeScalars.append(scalar)
                        index = scalars.index(after: index)
                    }
                    if found.lowercased() == name {
                        _ = skip(past: ">")
                        return
                    }
                    index = scalars.index(after: start)
                } else {
                    index = scalars.index(after: index)
                }
            }
        }

        /// The text of the entity that starts at the current position, just
        /// after its `&`, with the position moved past it. `nil` when the
        /// `&` doesn't start one, in which case it stays where it was.
        mutating func entity() -> String? {
            var name = ""
            var at = index
            while at < scalars.endIndex, name.unicodeScalars.count < 12 {
                let scalar = scalars[at]
                if scalar == ";" {
                    guard let decoded = HTMLText.entity(named: name) else { return nil }
                    index = scalars.index(after: at)
                    return decoded
                }
                guard scalar == "#" || scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) else { return nil }
                name.unicodeScalars.append(scalar)
                at = scalars.index(after: at)
            }
            return nil
        }

        private func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
            scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == ":" || scalar == "-" || scalar == "_"
        }
    }

    /// The text for a character reference or a named entity, from the
    /// names XHTML and most HTML use.
    private static func entity(named name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(scalar)
        }
        if let index = latin1.firstIndex(of: name) {
            return String(Unicode.Scalar(UInt8(160 + index)))
        }
        return others[name]
    }

    /// The names of U+00A0 through U+00FF, in order.
    private static let latin1 = [
        "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf", "laquo", "not", "shy", "reg", "macr",
        "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest",
        "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc", "Euml", "Igrave", "Iacute", "Icirc", "Iuml",
        "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times", "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
        "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml",
        "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml",
    ]

    private static let others: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "zwnj": "\u{200C}", "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "lsquo": "\u{2018}", "rsquo": "\u{2019}", "sbquo": "\u{201A}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}", "dagger": "\u{2020}", "Dagger": "\u{2021}",
        "bull": "\u{2022}", "hellip": "\u{2026}", "permil": "\u{2030}", "prime": "\u{2032}", "Prime": "\u{2033}",
        "lsaquo": "\u{2039}", "rsaquo": "\u{203A}", "oline": "\u{203E}", "euro": "\u{20AC}", "trade": "\u{2122}",
        "larr": "\u{2190}", "uarr": "\u{2191}", "rarr": "\u{2192}", "darr": "\u{2193}", "harr": "\u{2194}",
        "minus": "\u{2212}", "lowast": "\u{2217}", "radic": "\u{221A}", "infin": "\u{221E}", "ne": "\u{2260}", "equiv": "\u{2261}",
        "le": "\u{2264}", "ge": "\u{2265}", "loz": "\u{25CA}", "spades": "\u{2660}", "clubs": "\u{2663}", "hearts": "\u{2665}", "diams": "\u{2666}",
        "OElig": "\u{152}", "oelig": "\u{153}", "Scaron": "\u{160}", "scaron": "\u{161}", "Yuml": "\u{178}", "fnof": "\u{192}", "circ": "\u{2C6}", "tilde": "\u{2DC}",
    ]
}
