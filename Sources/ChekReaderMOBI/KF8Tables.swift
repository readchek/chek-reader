import ChekReaderCore

/// The tables KF8 uses to cut its XHTML into one text stream: skeletons
/// (each file's outer markup) and fragments (the content inserted into
/// them), as KindleUnpack's `mobi_k8proc.py` reads and rebuilds them.
enum KF8Tables {
    /// A file's outer markup, stored at ``start`` in the text and followed
    /// directly by its ``fragmentCount`` fragments.
    struct Skeleton: Sendable, Equatable {
        let fragmentCount: Int
        let start: Int
        let length: Int
    }

    /// Content inserted into a skeleton.
    struct Fragment: Sendable, Equatable {
        /// Where the fragment goes, as a position in the rebuilt text: the
        /// skeleton's start plus the offset into the skeleton as built so far.
        let insertPosition: Int
        /// The file the fragment belongs to.
        let fileNumber: Int
        let length: Int
    }

    /// A rebuilt file and the text positions it covers, which KF8 links
    /// and the NCX refer to.
    struct Part: Sendable, Equatable {
        var bytes: [UInt8]
        let start: Int
        let end: Int
    }

    /// Skeleton entries: tag 1 is the fragment count, tag 6 the start and length.
    static func skeletons(_ index: MOBIIndex) throws(ReaderError) -> [Skeleton] {
        var skeletons: [Skeleton] = []
        for entry in index.entries {
            guard let count = entry.value(1), let start = entry.value(6, 0), let length = entry.value(6, 1) else {
                throw .malformed(reason: "A KF8 skeleton entry is missing its position or fragment count.")
            }
            skeletons.append(Skeleton(fragmentCount: count, start: start, length: length))
        }
        return skeletons
    }

    /// Fragment entries: the name is the insert position in decimal, tag 3
    /// the file number, and tag 6 the start and length.
    static func fragments(_ index: MOBIIndex) throws(ReaderError) -> [Fragment] {
        var fragments: [Fragment] = []
        for entry in index.entries {
            guard let insertPosition = Int(String(decoding: entry.name, as: UTF8.self)),
                  let length = entry.value(6, 1)
            else {
                throw .malformed(reason: "A KF8 fragment entry is missing its insert position or length.")
            }
            fragments.append(Fragment(insertPosition: insertPosition, fileNumber: entry.value(3) ?? 0, length: length))
        }
        return fragments
    }

    /// Rebuilds each file by inserting its fragments into its skeleton.
    ///
    /// - Parameters:
    ///   - limit: The most bytes all parts may total, since a hostile
    ///     table could reuse the same text for every file.
    ///   - warnings: Receives repairs that didn't stop the rebuild.
    static func parts(
        text: [UInt8],
        skeletons: [Skeleton],
        fragments: [Fragment],
        limit: Int,
        warnings: inout [String]
    ) throws(ReaderError) -> [Part] {
        var parts: [Part] = []
        var nextFragment = 0
        var total = 0
        for (number, skeleton) in skeletons.enumerated() {
            try ReaderError.checkCancellation()
            guard skeleton.start >= 0, skeleton.length >= 0, skeleton.start <= text.count - skeleton.length else {
                throw .malformed(reason: "KF8 skeleton \(number) lies outside the text.")
            }
            guard skeleton.fragmentCount >= 0, skeleton.fragmentCount <= fragments.count - nextFragment else {
                throw .malformed(reason: "KF8 skeleton \(number) has more fragments than the fragment table.")
            }
            var bytes = Array(text[skeleton.start..<skeleton.start + skeleton.length])
            var base = skeleton.start + skeleton.length
            for _ in 0..<skeleton.fragmentCount {
                let fragment = fragments[nextFragment]
                nextFragment += 1
                guard fragment.length >= 0, base <= text.count - fragment.length else {
                    throw .malformed(reason: "A KF8 fragment in skeleton \(number) lies outside the text.")
                }
                let insert = fragment.insertPosition - skeleton.start
                guard insert >= 0, insert <= bytes.count else {
                    throw .malformed(reason: "A KF8 fragment in skeleton \(number) is inserted outside its file.")
                }
                // KindleUnpack repairs an insert position inside a tag from
                // the fragment's selector; that's rare enough to report instead.
                let lastOpen = bytes[..<insert].lastIndex(of: Markup.lessThan) ?? -1
                let lastClose = bytes[..<insert].lastIndex(of: Markup.greaterThan) ?? -1
                if lastOpen > lastClose {
                    warnings.append("A fragment of KF8 file \(number) is inserted inside a tag; the file may display incorrectly.")
                }
                bytes.insert(contentsOf: text[base..<base + fragment.length], at: insert)
                base += fragment.length
            }
            total += bytes.count
            guard total <= limit else {
                throw .limitExceeded(.uncompressedBytes)
            }
            parts.append(Part(bytes: bytes, start: skeleton.start, end: base))
        }
        return parts
    }

    /// The text split into flows at the FDST record's offsets. Flow 0 is
    /// the XHTML; the others are stylesheets and SVG images.
    static func flows(text: [UInt8], fdst: [UInt8]?, warnings: inout [String]) -> [[UInt8]] {
        guard let fdst else { return [text] }
        let bytes = BigEndianBytes(fdst, name: "FDST record")
        guard bytes.has("FDST", at: 0), let count = bytes.optionalUInt32(at: 8).map({ Int($0) }), count >= 1 else {
            warnings.append("The KF8 FDST record is damaged; stylesheets may be missing.")
            return [text]
        }
        var starts: [Int] = []
        for flow in 0..<min(count, bytes.count / 8) {
            guard let start = bytes.optionalUInt32(at: 12 + flow * 8).map({ Int($0) }) else { break }
            starts.append(start)
        }
        starts.append(text.count)
        guard starts.count == count + 1, starts.first == 0, zip(starts, starts.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            warnings.append("The KF8 FDST record's flows are out of order; stylesheets may be missing.")
            return [text]
        }
        return zip(starts, starts.dropFirst()).map { Array(text[$0..<$1]) }
    }
}
