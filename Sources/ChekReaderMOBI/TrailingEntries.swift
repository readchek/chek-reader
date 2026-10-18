/// The extra data some writers append to each text record, after the
/// compressed text, such as multibyte overlap and indexing hints.
///
/// The MOBI header's extra data flags say which entries are present. Each
/// flag above bit 0 adds an entry that ends in its own size, written
/// backward as a variable-width integer. Bit 0 adds the multibyte overlap,
/// whose size is in the low two bits of the last remaining byte. This
/// follows KindleUnpack's `getSizeOfTrailingDataEntries`.
enum TrailingEntries {
    /// The length of the text in `record` once its trailing entries are removed.
    static func textLength(of record: [UInt8], flags: UInt16) -> Int {
        let size = record.count
        var trailing = 0
        var testFlags = flags >> 1
        while testFlags != 0 {
            if testFlags & 1 != 0 {
                trailing += entrySize(record, end: size - trailing)
            }
            testFlags >>= 1
        }
        if flags & 1 != 0, size - trailing - 1 >= 0 {
            trailing += Int(record[size - trailing - 1] & 0x3) + 1
        }
        // A size that runs past the start of the record means the entries
        // are damaged; there's no text left to keep.
        return max(0, size - trailing)
    }

    /// The size of the entry that ends at `end`, read backward: each byte
    /// gives seven bits, and the byte with its high bit set is the last
    /// read. At most four bytes are read, as in KindleUnpack.
    static func entrySize(_ record: [UInt8], end: Int) -> Int {
        guard end > 0, end <= record.count else { return 0 }
        var result = 0
        var shift = 0
        var position = end
        while true {
            let byte = record[position - 1]
            result |= Int(byte & 0x7F) << shift
            shift += 7
            position -= 1
            if byte & 0x80 != 0 || shift >= 28 || position == 0 {
                return result
            }
        }
    }
}
