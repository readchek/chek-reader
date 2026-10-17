public import ChekReaderCore
import Foundation
public import Observation

/// Drives one reading session at a time.
///
/// Every `open` starts a new session and cancels the previous one. Work
/// that finishes after its session was replaced is dropped, so a slow open
/// can never overwrite a newer one.
@MainActor
@Observable
public final class ReaderController {
    public enum State: Equatable, Sendable {
        case idle
        case opening
        case ready
        case failed(ReaderError)
        case closing
        case closed
    }

    public private(set) var state: State = .idle
    /// The format of the current session, once it is known.
    public private(set) var format: ReaderFormat?
    /// The current position. Observing it does not redraw views that only
    /// read ``state``.
    public private(set) var location: Locator?

    @ObservationIgnored private var session = 0

    public init() {}

    /// Opens a publication, replacing any open session.
    ///
    /// Returns once the publication is ready. If another `open` or
    /// ``close()`` starts first, this call returns without changing state.
    public func open(_ source: PublicationSource, at location: Locator? = nil) async throws(ReaderError) {
        session += 1
        let current = session
        state = .opening
        format = nil
        self.location = location

        let detected: ReaderFormat?
        do {
            detected = try await Self.detectFormat(of: source)
        } catch {
            guard current == session else { return }
            return try fail(error)
        }
        guard current == session else { return }

        guard let detected else {
            return try fail(.unsupportedFormat(fileName: Self.fileName(of: source)))
        }
        format = detected
        do {
            _ = try ReaderFormats.module(for: detected)
        } catch {
            return try fail(error)
        }
        // Format engines land milestone by milestone.
        try fail(.notYetImplemented(detected))
    }

    /// Ends the session.
    public func close() async {
        session += 1
        guard state != .idle, state != .closed else { return }
        state = .closing
        state = .closed
    }

    private func fail(_ error: ReaderError) throws(ReaderError) {
        state = .failed(error)
        throw error
    }

    nonisolated private static func detectFormat(of source: PublicationSource) async throws(ReaderError) -> ReaderFormat? {
        switch source {
        case .file(let url):
            let prefix: Data
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                prefix = try handle.read(upToCount: FormatSniffer.prefixLength) ?? Data()
            } catch {
                throw .malformed(reason: "The file could not be read.")
            }
            return FormatSniffer.format(of: prefix, fileName: url.lastPathComponent)
        case .data(let data, let fileName):
            return FormatSniffer.format(of: data, fileName: fileName)
        case .remote(let url, _):
            return FormatSniffer.format(forFileName: url.lastPathComponent)
        case .provider(let provider):
            return provider.format
        case .pages:
            return .cbz
        }
    }

    nonisolated private static func fileName(of source: PublicationSource) -> String? {
        switch source {
        case .file(let url), .remote(let url, _): url.lastPathComponent
        case .data(_, let fileName): fileName
        case .provider, .pages: nil
        }
    }
}
