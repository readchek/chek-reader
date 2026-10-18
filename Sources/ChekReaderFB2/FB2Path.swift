/// Turns names from the book into file names for generated resources.
enum FB2Path {
    /// `name` with every character other than ASCII letters, digits, `.`,
    /// `-` and `_` replaced by `_`, so ids such as `../cover` or `a b`
    /// can't leave their folder or need escaping in an href. Returns
    /// `nil` when nothing usable is left.
    static func component(_ name: String) -> String? {
        var result = ""
        for scalar in name.unicodeScalars.prefix(100) {
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_", ".":
                result.unicodeScalars.append(scalar)
            default:
                result += "_"
            }
        }
        // A leading dot would make a hidden file or a `..` segment.
        while result.hasPrefix(".") {
            result.removeFirst()
        }
        return result.contains(where: { $0 != "_" }) ? result : nil
    }

    /// `name`, or `name` with a number added before its extension, so that
    /// it isn't in `used`. Adds the result to `used`.
    static func unique(_ name: String, extension fileExtension: String, in used: inout Set<String>) -> String {
        let suffix = fileExtension.isEmpty ? "" : "." + fileExtension
        var candidate = name + suffix
        var number = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(name)-\(number)\(suffix)"
            number += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
