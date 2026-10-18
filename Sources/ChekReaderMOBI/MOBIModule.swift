public import ChekReaderCore
import Foundation

/// DRM-free MOBI and AZW3 (KF8).
///
/// Register it once at launch: `ReaderFormats.register(MOBIModule.self)`.
///
/// The whole file is read when it opens, and its text decompressed and
/// rebuilt into documents held in memory:
///
/// - **KF8**, in an AZW3 file or the second half of a joint MOBI file,
///   opens as XHTML files, one per file in the original book, with its
///   stylesheets, images and fonts. The publication's format is
///   ``ReaderFormat/azw3``.
/// - **MOBI 6** opens as HTML documents split at the book's page breaks,
///   with its images. The publication's format is ``ReaderFormat/mobi``.
///
/// Whichever format the file was detected as, the KF8 version is opened
/// when the file has one. Books protected with Mobipocket DRM fail with
/// ``ReaderError/drmProtected(scheme:)``; an app that can decrypt them
/// supplies the decrypted file through a ``ResourceProvider``, which is
/// asked for ``PublicationSource/wholePublicationHref``.
public enum MOBIModule: ReaderFormatModule {
    /// MOBI and AZW3, which share a file layout.
    public static let formats: [ReaderFormat] = [.mobi, .azw3]

    /// Reads and parses a MOBI, AZW3 or joint MOBI/KF8 file.
    ///
    /// - Throws: ``ReaderError/drmProtected(scheme:)`` for Mobipocket DRM,
    ///   ``ReaderError/malformed(reason:)`` for a damaged file,
    ///   ``ReaderError/limitExceeded(_:)`` when the file or its text is
    ///   larger than `limits` allow, and ``ReaderError/cancelled``.
    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        let data = try await source.wholeFile(limits: limits)
        try ReaderError.checkCancellation()
        return try MOBIParser.parse(data, limits: limits)
    }
}
