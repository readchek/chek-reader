/// A problem found while opening a publication that didn't stop it opening.
///
/// Malformed but readable publications open in recovery mode. Each repair
/// or omission is recorded as a warning, so apps can log it or tell the
/// publisher.
public struct PublicationWarning: Hashable, Sendable, CustomStringConvertible {
    /// What was wrong and what the reader did about it.
    public var message: String
    /// The resource the warning is about, if any.
    public var href: String?

    public init(_ message: String, href: String? = nil) {
        self.message = message
        self.href = href
    }

    public var description: String {
        if let href {
            "\(href): \(message)"
        } else {
            message
        }
    }
}
