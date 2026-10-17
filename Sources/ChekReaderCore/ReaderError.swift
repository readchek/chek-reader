public import Foundation

/// Every failure the reader reports.
///
/// Messages are written for the developer integrating the package and say
/// what to do next.
public enum ReaderError: Error, Hashable, Sendable {
    /// The format is known, but the app does not link or register its product.
    case formatNotIncluded(ReaderFormat)
    /// The content is not a format the reader supports.
    case unsupportedFormat(fileName: String?)
    /// The publication is encrypted with a DRM scheme the package does not decrypt.
    case drmProtected(scheme: String)
    /// The file is damaged or does not follow its format's rules.
    case malformed(reason: String)
    /// The publication exceeds one of the configured ``ReaderLimits``.
    case limitExceeded(ReaderLimits.Limit)
    /// A remote source failed. Remote failures can usually be retried.
    case network(reason: String)
    /// The format's product is linked but does not open publications yet.
    case notYetImplemented(ReaderFormat)

    /// Whether repeating the same operation might succeed.
    public var isRetryable: Bool {
        switch self {
        case .network: true
        default: false
        }
    }
}

extension ReaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .formatNotIncluded(let format):
            "\(format.name) support is not included in this app."
        case .unsupportedFormat(let fileName):
            if let fileName {
                "\(fileName) is not in a format Chek Reader supports."
            } else {
                "This content is not in a format Chek Reader supports."
            }
        case .drmProtected(let scheme):
            "This publication is protected with \(scheme). Chek Reader does not decrypt DRM."
        case .malformed(let reason):
            "The publication is damaged: \(reason)"
        case .limitExceeded(let limit):
            "The publication exceeds the \(limit.rawValue) limit."
        case .network(let reason):
            "The publication could not be downloaded: \(reason)"
        case .notYetImplemented(let format):
            "Opening \(format.name) publications is not implemented yet."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .formatNotIncluded(let format):
            "Add the \(format.product) product to the app target and register it with ReaderFormats.register(_:)."
        case .drmProtected:
            "Supply a ResourceProvider that returns decrypted resources."
        case .limitExceeded:
            "Raise the limit in ReaderLimits if the publication is trusted."
        case .network:
            "Check the connection and try again."
        default:
            nil
        }
    }
}
