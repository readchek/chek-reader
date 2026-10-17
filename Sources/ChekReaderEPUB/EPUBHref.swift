import Foundation

/// Resolves hrefs found in EPUB documents to paths from the publication's root.
enum EPUBHref {
    /// Resolves `href`, written in the document at `base`, to a percent-decoded
    /// path with its fragment kept.
    ///
    /// Returns `nil` for hrefs with a scheme, such as `https:` or `mailto:`,
    /// and for paths that climb above the publication's root.
    static func resolve(_ href: String, from base: String) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasScheme(trimmed) {
            return nil
        }
        var path = Substring(trimmed)
        var fragment: Substring?
        if let hash = path.firstIndex(of: "#") {
            fragment = path[path.index(after: hash)...]
            path = path[..<hash]
        }
        if let query = path.firstIndex(of: "?") {
            path = path[..<query]
        }
        let decoded = String(path).removingPercentEncoding ?? String(path)

        var components: [Substring]
        if decoded.isEmpty {
            // A bare fragment points into the base document itself.
            components = base.split(separator: "/")
        } else if decoded.hasPrefix("/") {
            components = []
        } else {
            components = base.split(separator: "/").dropLast()
        }
        if !decoded.isEmpty {
            for component in decoded.split(separator: "/") {
                switch component {
                case ".":
                    continue
                case "..":
                    guard components.popLast() != nil else { return nil }
                default:
                    components.append(component)
                }
            }
        }
        guard !components.isEmpty else { return nil }

        let resolved = components.joined(separator: "/")
        if let fragment, !fragment.isEmpty {
            return resolved + "#" + (String(fragment).removingPercentEncoding ?? String(fragment))
        }
        return resolved
    }

    /// Whether `href` starts with a URI scheme such as `https:`.
    private static func hasScheme(_ href: String) -> Bool {
        guard let colon = href.firstIndex(of: ":") else { return false }
        let scheme = href[..<colon]
        guard let first = scheme.first, first.isLetter, first.isASCII else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
    }
}
