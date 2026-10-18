import ChekReaderCore

/// Reads and decompresses a part's text records into its raw markup.
enum MOBIText {
    /// The uncompressed text of the part whose header record is `partStart`.
    ///
    /// - Throws: ``ReaderError/limitExceeded(_:)`` when the text expands
    ///   past ``ReaderLimits/maxUncompressedBytes`` or by more than
    ///   ``ReaderLimits/maxCompressionRatio``.
    static func read(
        _ database: PalmDatabase,
        header: MOBIHeader,
        partStart: Int,
        limits: ReaderLimits
    ) throws(ReaderError) -> [UInt8] {
        let first = partStart + 1
        guard header.textRecordCount > 0 else {
            throw .malformed(reason: "The MOBI file has no text records.")
        }
        guard first + header.textRecordCount <= database.recordCount else {
            throw .malformed(reason: "The MOBI header lists \(header.textRecordCount) text records, more than the file has.")
        }
        let limit = Int(clamping: limits.maxUncompressedBytes)

        var huffCDIC: HuffCDIC?
        if header.compression == .huffCDIC {
            huffCDIC = try loadHuffCDIC(database, header: header, partStart: partStart)
        }

        var text: [UInt8] = []
        var compressedLength = 0
        for index in first..<first + header.textRecordCount {
            try ReaderError.checkCancellation()
            let record = try database.record(index)
            let length = TrailingEntries.textLength(of: record, flags: header.extraDataFlags)
            let input = Array(record[0..<length])
            compressedLength += input.count
            let remaining = limit - text.count
            switch header.compression {
            case .none:
                guard input.count <= remaining else { throw .limitExceeded(.uncompressedBytes) }
                text += input
            case .palmDOC:
                text += try PalmDOC.decompress(input, limit: remaining)
            case .huffCDIC:
                // Set above whenever the compression is HUFF/CDIC. Calling
                // through the optional mutates the decoder in place, so its
                // dictionary isn't copied for every record.
                text += try huffCDIC?.decompress(input, limit: remaining) ?? []
            }
            if compressedLength > 0, Double(text.count) > Double(compressedLength) * limits.maxCompressionRatio {
                throw .limitExceeded(.compressionRatio)
            }
        }
        // Some writers leave bytes past the recorded length in the last
        // record; they aren't part of the text.
        if header.textLength < text.count {
            text.removeSubrange(header.textLength...)
        }
        return text
    }

    private static func loadHuffCDIC(_ database: PalmDatabase, header: MOBIHeader, partStart: Int) throws(ReaderError) -> HuffCDIC {
        guard let huffIndex = MOBIHeader.record(header.huffRecordIndex, partStart: partStart, recordCount: database.recordCount),
              header.huffRecordCount >= 1,
              Int(header.huffRecordCount) <= database.recordCount - huffIndex
        else {
            throw .malformed(reason: "The MOBI file uses HUFF/CDIC compression but its HUFF records are missing.")
        }
        var cdics: [[UInt8]] = []
        for index in huffIndex + 1..<huffIndex + Int(header.huffRecordCount) {
            cdics.append(try database.record(index))
        }
        return try HuffCDIC(huff: try database.record(huffIndex), cdics: cdics)
    }
}
