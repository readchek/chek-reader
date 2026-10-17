import ChekReaderCore

/// An INDX index, the structure MOBI and KF8 use for the table of
/// contents, KF8's skeleton and fragment tables, and the guide.
///
/// The first record is a header with a TAGX table describing each entry's
/// tags. The records after it hold the entries, located through an IDXT
/// table of offsets; each entry is a name followed by control bytes and
/// variable-width tag values. String values live in CNCX records after the
/// entry records and are referred to by offset. This follows KindleUnpack's
/// `mobi_index.py`.
struct MOBIIndex: Sendable {
    struct Entry: Sendable, Equatable {
        /// The entry's name, such as a fragment's insert position in decimal.
        let name: [UInt8]
        /// Each tag's values. A tag may repeat its values-per-entry group.
        let tags: [UInt8: [Int]]

        /// The `index`th value of `tag`.
        func value(_ tag: UInt8, _ index: Int = 0) -> Int? {
            guard let values = tags[tag], index < values.count else { return nil }
            return values[index]
        }
    }

    /// One row of the TAGX table.
    struct TagDefinition: Sendable, Equatable {
        let tag: UInt8
        let valuesPerEntry: Int
        let mask: UInt8
        /// Marks the end of one control byte's tags.
        let isEndOfControlByte: Bool
    }

    let entries: [Entry]
    /// CNCX strings by offset. Each CNCX record after the first adds 0x10000
    /// to its offsets, as KindleUnpack numbers them.
    let strings: [Int: [UInt8]]

    /// Reads the index whose header is record `index`.
    init(_ database: PalmDatabase, index: Int, limits: ReaderLimits) throws(ReaderError) {
        let main = try database.record(index)
        let header = BigEndianBytes(main, name: "index record \(index)")
        guard header.has("INDX", at: 0) else {
            throw .malformed(reason: "Record \(index) should be an index but isn't.")
        }
        let recordCount = Int(try header.uint32(at: 24))
        let cncxCount = Int(try header.uint32(at: 52))
        guard recordCount <= database.recordCount - index - 1,
              cncxCount <= database.recordCount - index - 1 - recordCount
        else {
            throw .malformed(reason: "The index at record \(index) lists more records than the file has.")
        }
        var records: [[UInt8]] = []
        for offset in 0..<recordCount {
            records.append(try database.record(index + 1 + offset))
        }
        var cncx: [[UInt8]] = []
        for offset in 0..<cncxCount {
            cncx.append(try database.record(index + 1 + recordCount + offset))
        }
        try self.init(main: main, records: records, cncx: cncx, maxEntries: limits.maxArchiveEntries)
    }

    /// Reads an index from its header record, entry records and CNCX records.
    init(main: [UInt8], records: [[UInt8]], cncx: [[UInt8]], maxEntries: Int) throws(ReaderError) {
        let header = BigEndianBytes(main, name: "index header")
        guard header.has("INDX", at: 0) else {
            throw .malformed(reason: "An index header record doesn't start with INDX.")
        }
        let tagSectionStart = Int(try header.uint32(at: 4))
        let (controlByteCount, definitions) = try Self.readTagSection(header, at: tagSectionStart)

        var strings: [Int: [UInt8]] = [:]
        for (number, record) in cncx.enumerated() {
            for (offset, string) in Self.readCNCX(record) {
                strings[offset + number * 0x10000] = string
            }
        }
        self.strings = strings

        var entries: [Entry] = []
        for (number, record) in records.enumerated() {
            let bytes = BigEndianBytes(record, name: "index record \(number + 1)")
            guard bytes.has("INDX", at: 0) else {
                throw .malformed(reason: "An index entry record doesn't start with INDX.")
            }
            let idxtStart = Int(try bytes.uint32(at: 20))
            let entryCount = Int(try bytes.uint32(at: 24))
            guard bytes.has("IDXT", at: idxtStart), entryCount <= (record.count - idxtStart - 4) / 2 else {
                throw .malformed(reason: "An index record's IDXT table is missing or too short.")
            }
            guard entries.count + entryCount <= maxEntries else {
                throw .limitExceeded(.archiveEntries)
            }
            var positions: [Int] = []
            for entry in 0..<entryCount {
                positions.append(Int(try bytes.uint16(at: idxtStart + 4 + entry * 2)))
            }
            // The last entry ends where the IDXT table starts.
            positions.append(idxtStart)
            for entry in 0..<entryCount {
                let start = positions[entry]
                let end = positions[entry + 1]
                guard start < end, end <= idxtStart else {
                    throw .malformed(reason: "An index entry's offsets are out of order.")
                }
                let nameLength = Int(try bytes.uint8(at: start))
                guard start + 1 + nameLength <= end else {
                    throw .malformed(reason: "An index entry's name runs past the entry.")
                }
                let name = Array(record[start + 1..<start + 1 + nameLength])
                let tags = try Self.tagValues(
                    record,
                    from: start + 1 + nameLength,
                    to: end,
                    controlByteCount: controlByteCount,
                    definitions: definitions
                )
                entries.append(Entry(name: name, tags: tags))
            }
        }
        self.entries = entries
    }

    /// The control byte count and tag definitions of the TAGX section at `start`.
    static func readTagSection(_ bytes: BigEndianBytes, at start: Int) throws(ReaderError) -> (Int, [TagDefinition]) {
        guard bytes.has("TAGX", at: start) else {
            throw .malformed(reason: "An index has no TAGX table.")
        }
        let length = Int(try bytes.uint32(at: start + 4))
        let controlByteCount = Int(try bytes.uint32(at: start + 8))
        guard length >= 12, bytes.contains(start, length), controlByteCount <= 16 else {
            throw .malformed(reason: "An index's TAGX table is damaged.")
        }
        var definitions: [TagDefinition] = []
        for offset in stride(from: start + 12, to: start + length - 3, by: 4) {
            definitions.append(TagDefinition(
                tag: bytes.bytes[offset],
                valuesPerEntry: Int(bytes.bytes[offset + 1]),
                mask: bytes.bytes[offset + 2],
                isEndOfControlByte: bytes.bytes[offset + 3] == 1
            ))
        }
        return (controlByteCount, definitions)
    }

    /// Decodes an entry's tag values from `start` up to `end`, following
    /// KindleUnpack's `getTagMap`.
    static func tagValues(
        _ record: [UInt8],
        from start: Int,
        to end: Int,
        controlByteCount: Int,
        definitions: [TagDefinition]
    ) throws(ReaderError) -> [UInt8: [Int]] {
        guard start + controlByteCount <= end else {
            throw .malformed(reason: "An index entry is shorter than its control bytes.")
        }
        // Which tags are present, and either how many value groups each has
        // or how many bytes its values take.
        var present: [(definition: TagDefinition, count: Int?, byteLength: Int?)] = []
        var controlByteIndex = 0
        var dataPosition = start + controlByteCount
        for definition in definitions {
            if definition.isEndOfControlByte {
                controlByteIndex += 1
                continue
            }
            guard controlByteIndex < controlByteCount else {
                throw .malformed(reason: "An index's TAGX table uses more control bytes than its entries have.")
            }
            var mask = definition.mask
            var value = record[start + controlByteIndex] & mask
            guard value != 0 else { continue }
            if value == mask {
                if mask.nonzeroBitCount > 1 {
                    // Every bit of a multi-bit mask set means a variable-width
                    // byte length follows the control bytes.
                    let (length, consumed) = try VariableWidth.forward(record, at: dataPosition, end: end)
                    dataPosition += consumed
                    present.append((definition: definition, count: nil, byteLength: length))
                } else {
                    present.append((definition: definition, count: 1, byteLength: nil))
                }
            } else {
                while mask & 1 == 0 {
                    mask >>= 1
                    value >>= 1
                }
                present.append((definition: definition, count: Int(value), byteLength: nil))
            }
        }

        var tags: [UInt8: [Int]] = [:]
        for (definition, count, byteLength) in present {
            var values: [Int] = []
            if let count {
                for _ in 0..<count * definition.valuesPerEntry {
                    let (value, consumed) = try VariableWidth.forward(record, at: dataPosition, end: end)
                    dataPosition += consumed
                    values.append(value)
                }
            } else if let byteLength {
                guard byteLength <= end - dataPosition else {
                    throw .malformed(reason: "An index entry's values run past the entry.")
                }
                let valuesEnd = dataPosition + byteLength
                while dataPosition < valuesEnd {
                    let (value, consumed) = try VariableWidth.forward(record, at: dataPosition, end: valuesEnd)
                    dataPosition += consumed
                    values.append(value)
                }
            }
            tags[definition.tag] = values
        }
        return tags
    }

    /// The strings in a CNCX record by offset: each a variable-width length
    /// then that many bytes, until the record ends or a zero byte.
    static func readCNCX(_ record: [UInt8]) -> [Int: [UInt8]] {
        var strings: [Int: [UInt8]] = [:]
        var offset = 0
        while offset < record.count, record[offset] != 0 {
            guard let number = try? VariableWidth.forward(record, at: offset, end: record.count),
                  number.0 <= record.count - offset - number.1
            else { break }
            let (length, consumed) = number
            let start = offset + consumed
            strings[offset] = Array(record[start..<start + length])
            offset = start + length
        }
        return strings
    }
}

/// The variable-width integers in MOBI indexes.
enum VariableWidth {
    /// The most bytes one integer may take. Five bytes hold 35 bits, more
    /// than any offset in a file this package will open.
    static let maxLength = 5

    /// The integer at `offset`: seven bits per byte, most significant
    /// first, ending with the byte whose high bit is set. Returns the value
    /// and how many bytes it took.
    static func forward(_ bytes: [UInt8], at offset: Int, end: Int) throws(ReaderError) -> (Int, Int) {
        var value = 0
        var consumed = 0
        let end = min(end, bytes.count)
        while true {
            guard offset + consumed < end, offset >= 0, consumed < maxLength else {
                throw .malformed(reason: "An index entry has a damaged number.")
            }
            let byte = bytes[offset + consumed]
            consumed += 1
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 != 0 {
                return (value, consumed)
            }
        }
    }
}
