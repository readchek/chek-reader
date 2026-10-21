public import Foundation

/// How ``Publication/search(for:options:)`` matches text.
public struct SearchOptions: Hashable, Sendable {
    /// Whether `a` and `A` differ. Off by default.
    public var caseSensitive: Bool
    /// Whether `e` and `é` differ. Off by default.
    public var diacriticSensitive: Bool
    /// The most results to return. Searching stops once they're found.
    public var limit: Int

    public init(caseSensitive: Bool = false, diacriticSensitive: Bool = false, limit: Int = 1000) {
        self.caseSensitive = caseSensitive
        self.diacriticSensitive = diacriticSensitive
        self.limit = max(0, limit)
    }

    /// The matching options for Foundation's string search.
    package var compareOptions: String.CompareOptions {
        var options: String.CompareOptions = []
        if !caseSensitive { options.insert(.caseInsensitive) }
        if !diacriticSensitive { options.insert(.diacriticInsensitive) }
        return options
    }
}
