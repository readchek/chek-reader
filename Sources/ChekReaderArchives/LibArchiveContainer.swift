import ChekReaderCore
import Foundation
#if canImport(ArchiveKit)
import ArchiveKit
#else
import CLibArchive
#endif

/// A RAR or 7-Zip archive held in memory, read through libarchive.
///
/// libarchive reads an archive front to back, so every resource read
/// opens the archive again and skips to the entry. RAR archives are often
/// solid, where skipping means decompressing everything before the entry,
/// so reading pages in order is much cheaper than jumping around.
struct LibArchiveContainer: PublicationContainer {
    private let data: Data
    private let format: ReaderFormat
    private let limits: ReaderLimits
    /// Each regular file's size, or `nil` when the archive doesn't say.
    private let entries: [String: Int64?]
    let paths: Set<String>?

    /// Lists the archive's entries, checking them against `limits`.
    init(data: Data, format: ReaderFormat, limits: ReaderLimits) throws(ReaderError) {
        self.data = data
        self.format = format
        self.limits = limits
        var entries: [String: Int64?] = [:]
        var total: Int64 = 0
        try unsafe Self.read(data, format: format) { (archive) throws(ReaderError) in
            try unsafe Self.forEachEntry(in: archive) { (entry) throws(ReaderError) in
                guard let path = unsafe Self.path(of: entry) else { return }
                let size = unsafe Self.size(of: entry)
                entries[path] = size
                guard entries.count <= limits.maxArchiveEntries else {
                    throw .limitExceeded(.archiveEntries)
                }
                if let size {
                    guard size <= limits.maxResourceBytes else {
                        throw .limitExceeded(.resourceBytes)
                    }
                    total += size
                    guard total <= limits.maxUncompressedBytes else {
                        throw .limitExceeded(.uncompressedBytes)
                    }
                }
                unsafe archive_read_data_skip(archive)
            }
        }
        self.entries = entries
        paths = Set(entries.keys)
    }

    func data(at path: String) async throws(ReaderError) -> Data {
        guard let size = entries[path] else {
            throw .malformed(reason: "\(path) is not in the archive.")
        }
        try ReaderError.checkCancellation()
        return try unsafe Self.read(data, format: format) { (archive) throws(ReaderError) -> Data in
            var found: Data?
            try unsafe Self.forEachEntry(in: archive) { (entry) throws(ReaderError) in
                if unsafe Self.path(of: entry) == path {
                    found = try unsafe Self.readData(from: archive, size: size, limits: limits)
                    return
                }
                unsafe archive_read_data_skip(archive)
            }
            guard let found else {
                throw .malformed(reason: "\(path) is not in the archive.")
            }
            return found
        }
    }

    func length(of path: String) async -> Int64? {
        entries[path] ?? nil
    }

    // MARK: - libarchive

    private static let ok: Int32 = 0
    private static let eof: Int32 = 1
    private static let warn: Int32 = -20
    /// The file type bits of an entry's mode, and the value for a regular file.
    private static let typeMask: UInt32 = 0o170000
    private static let regularFile: UInt32 = 0o100000

    /// Opens the archive over `data` for `body`, and frees it afterwards.
    private static func read<T>(_ data: Data, format: ReaderFormat, _ body: (OpaquePointer) throws(ReaderError) -> T) throws(ReaderError) -> T {
        guard let archive = unsafe archive_read_new() else {
            throw .malformed(reason: "libarchive could not start. The process may be out of memory.")
        }
        defer { _ = unsafe archive_read_free(archive) }
        if format == .cbr {
            unsafe archive_read_support_format_rar(archive)
            unsafe archive_read_support_format_rar5(archive)
        } else {
            unsafe archive_read_support_format_7zip(archive)
        }
        // The bytes stay in place for the whole read, because `data`
        // holds them and the closure doesn't outlive this call.
        return try unsafe data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) throws(ReaderError) -> T in
            guard let base = unsafe bytes.baseAddress else {
                throw .malformed(reason: "The archive is empty.")
            }
            guard unsafe archive_read_open_memory(archive, base, bytes.count) == ok else {
                throw unsafe failure(archive, fallback: "The archive is not a \(format.name) file.")
            }
            return try unsafe body(archive)
        }
    }

    /// Calls `body` with each entry's header, in archive order. `body`
    /// reads or skips the entry's data before returning.
    private static func forEachEntry(in archive: OpaquePointer, _ body: (OpaquePointer) throws(ReaderError) -> Void) throws(ReaderError) {
        while true {
            try ReaderError.checkCancellation()
            var entry: OpaquePointer?
            let status = unsafe archive_read_next_header(archive, &entry)
            if status == eof { return }
            guard status == ok || status == warn else {
                throw unsafe failure(archive, fallback: "An entry's header is damaged.")
            }
            guard let entry = unsafe entry else { continue }
            let encrypted = unsafe archive_entry_is_data_encrypted(entry) != 0
            let hidden = unsafe archive_entry_is_metadata_encrypted(entry) != 0
            if encrypted || hidden {
                throw .drmProtected(scheme: "password")
            }
            try unsafe body(entry)
        }
    }

    /// The entry's path from the archive's root, or `nil` for anything
    /// but a regular file.
    private static func path(of entry: OpaquePointer) -> String? {
        let type = unsafe UInt32(archive_entry_filetype(entry))
        guard type & typeMask == regularFile else { return nil }
        guard let name = unsafe archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else { return nil }
        let raw = unsafe String(cString: name)
        var path = raw.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") { path.removeFirst(2) }
        while path.hasPrefix("/") { path.removeFirst() }
        return path.isEmpty ? nil : path
    }

    private static func size(of entry: OpaquePointer) -> Int64? {
        guard unsafe archive_entry_size_is_set(entry) != 0 else { return nil }
        let size = unsafe archive_entry_size(entry)
        return size >= 0 ? Int64(size) : nil
    }

    /// The current entry's data. A size the header promised is trusted
    /// only up to the limits; an entry that runs past it is damaged.
    private static func readData(from archive: OpaquePointer, size: Int64?, limits: ReaderLimits) throws(ReaderError) -> Data {
        let cap = Int(min(limits.maxResourceBytes, Int64(Int.max)))
        var data = Data()
        if let size {
            data.reserveCapacity(Int(min(size, Int64(cap))))
        }
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try ReaderError.checkCancellation()
            let read = unsafe chunk.withUnsafeMutableBytes { buffer in
                unsafe archive_read_data(archive, buffer.baseAddress, buffer.count)
            }
            if read == 0 { break }
            guard read > 0 else {
                throw unsafe failure(archive, fallback: "An entry's data is damaged.")
            }
            guard data.count + Int(read) <= cap else {
                throw .limitExceeded(.resourceBytes)
            }
            data.append(contentsOf: chunk[..<Int(read)])
        }
        if let size, Int64(data.count) != size {
            throw .malformed(reason: "An entry has \(data.count) bytes where its header promised \(size). The archive may be truncated.")
        }
        return data
    }

    /// libarchive's message for the last failure, as a reader error.
    private static func failure(_ archive: OpaquePointer, fallback: String) -> ReaderError {
        let message = unsafe archive_error_string(archive).map { unsafe String(cString: $0) } ?? fallback
        return .malformed(reason: "\(message) The archive may be damaged or not a comic archive.")
    }
}
