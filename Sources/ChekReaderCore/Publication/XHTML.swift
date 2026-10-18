import Foundation

/// Builds the XHTML documents that formats without their own HTML, such as
/// plain text, Markdown and FB2, are converted to before the web navigator
/// shows them.
package enum XHTML {
    /// The media type of every document ``document(title:language:body:stylesheets:)`` builds.
    package static let mediaType = "application/xhtml+xml"

    /// `text` with the characters that mean something in markup escaped,
    /// so it can go in element content or a double-quoted attribute.
    package static func escape(_ text: some StringProtocol) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text.unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            // Control characters other than tab and newlines aren't allowed in XML.
            case "\u{0}"..."\u{8}", "\u{B}", "\u{C}", "\u{E}"..."\u{1F}", "\u{FFFE}", "\u{FFFF}": continue
            default: result.unicodeScalars.append(character)
            }
        }
        return result
    }

    /// A complete XHTML document around `body`, which must already be
    /// well-formed XHTML.
    ///
    /// - Parameters:
    ///   - stylesheets: Hrefs of stylesheets, relative to the document.
    package static func document(title: String?, language: String?, body: String, stylesheets: [String] = []) -> Data {
        var head = "<meta charset=\"utf-8\"/>"
        head += "<title>\(escape(title ?? ""))</title>"
        for stylesheet in stylesheets {
            head += "<link rel=\"stylesheet\" type=\"text/css\" href=\"\(escape(stylesheet))\"/>"
        }
        let lang = language.map { " lang=\"\(escape($0))\" xml:lang=\"\(escape($0))\"" } ?? ""
        let document = """
            <?xml version="1.0" encoding="utf-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"\(lang)>
            <head>\(head)</head>
            <body>
            \(body)
            </body>
            </html>

            """
        return Data(document.utf8)
    }
}
