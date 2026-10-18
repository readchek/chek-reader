import Foundation

/// Builds small MOBI and KF8 files in tests, so no books are committed.
///
/// The file is a Palm database: record 0 with the PalmDOC, MOBI and EXTH
/// headers, then the text records, any index and FDST records, the
/// images, and the end-of-file record.
package struct MOBIFixture {
    package enum Compression {
        case none
        case palmDOC
    }

    /// One TAGX row for ``index(tags:entries:cncx:)``.
    package struct IndexTag {
        package var tag: UInt8
        package var valuesPerEntry: Int

        package init(_ tag: UInt8, valuesPerEntry: Int = 1) {
            self.tag = tag
            self.valuesPerEntry = valuesPerEntry
        }
    }

    package var text: [UInt8]
    package var compression: Compression = .none
    /// 65001 for UTF-8, 1252 for Windows-1252.
    package var encoding: UInt32 = 65001
    /// 8 makes it a KF8 book.
    package var version: UInt32 = 6
    package var fullName = "Fixture Title"
    package var locale: UInt32 = 9
    package var encryption: UInt16 = 0
    package var exth: [(type: UInt32, value: [UInt8])] = []
    package var extraDataFlags: UInt16 = 0
    /// Bytes appended to every text record, for trailing entries.
    package var trailer: [UInt8] = []
    package var recordSize = 4096
    /// Overrides the recorded text length.
    package var textLength: Int?
    package var ncx: [[UInt8]] = []
    package var skeletonIndex: [[UInt8]] = []
    package var fragmentIndex: [[UInt8]] = []
    package var fdst: [UInt8]?
    package var images: [[UInt8]] = []

    package init(text: String) {
        self.text = Array(text.utf8)
    }

    package init(bytes: [UInt8]) {
        text = bytes
    }

    /// Adds a string EXTH record.
    package mutating func add(exth type: UInt32, _ value: String) {
        exth.append((type: type, value: Array(value.utf8)))
    }

    /// Adds a numeric EXTH record.
    package mutating func add(exth type: UInt32, number: UInt32) {
        var value: [UInt8] = []
        value.append(be32: number)
        exth.append((type: type, value: value))
    }

    /// The text cut into records, before compression and trailers.
    package var textChunks: [[UInt8]] {
        stride(from: 0, to: max(text.count, 1), by: recordSize).map { Array(text[$0..<min(text.count, $0 + recordSize)]) }
    }

    package func data() -> Data {
        var records: [[UInt8]] = [[]]
        for chunk in textChunks {
            let stored = compression == .palmDOC ? Self.palmDOC(chunk) : chunk
            records.append(stored + trailer)
        }
        func place(_ group: [[UInt8]]) -> UInt32 {
            guard !group.isEmpty else { return 0xFFFF_FFFF }
            records += group
            return UInt32(records.count - group.count)
        }
        let ncxIndex = place(ncx)
        let skeleton = place(skeletonIndex)
        let fragment = place(fragmentIndex)
        let fdstIndex = place(fdst.map { [$0] } ?? [])
        let firstImage = place(images)
        records.append(Array("FLIS".utf8) + [UInt8](repeating: 0, count: 32))
        records.append([0xE9, 0x8E, 0x0D, 0x0A])
        records[0] = header(
            textRecordCount: textChunks.count,
            ncxIndex: ncxIndex,
            skeletonIndex: skeleton,
            fragmentIndex: fragment,
            fdstIndex: fdstIndex,
            firstImage: firstImage
        )
        return Self.database(records)
    }

    private func header(
        textRecordCount: Int,
        ncxIndex: UInt32,
        skeletonIndex: UInt32,
        fragmentIndex: UInt32,
        fdstIndex: UInt32,
        firstImage: UInt32
    ) -> [UInt8] {
        let headerLength = 0xF8
        var record = [UInt8](repeating: 0, count: 16 + headerLength)
        func put16(_ value: UInt16, at offset: Int) {
            record[offset] = UInt8(value >> 8)
            record[offset + 1] = UInt8(value & 0xFF)
        }
        func put32(_ value: UInt32, at offset: Int) {
            for index in 0..<4 {
                record[offset + index] = UInt8(value >> (24 - 8 * index) & 0xFF)
            }
        }
        // PalmDOC header.
        put16(compression == .palmDOC ? 2 : 1, at: 0)
        put32(UInt32(textLength ?? text.count), at: 4)
        put16(UInt16(textRecordCount), at: 8)
        put16(UInt16(recordSize), at: 10)
        put16(encryption, at: 12)
        // MOBI header.
        record.replaceSubrange(16..<20, with: Array("MOBI".utf8))
        put32(UInt32(headerLength), at: 0x14)
        put32(2, at: 0x18)
        put32(encoding, at: 0x1C)
        put32(0x1234_5678, at: 0x20)
        put32(version, at: 0x24)
        put32(locale, at: 0x5C)
        put32(firstImage, at: 0x6C)
        put32(exth.isEmpty ? 0 : 0x40, at: 0x80)
        put32(fdstIndex, at: 0xC0)
        put16(extraDataFlags, at: 0xF2)
        put32(ncxIndex, at: 0xF4)
        put32(fragmentIndex, at: 0xF8)
        put32(skeletonIndex, at: 0xFC)
        put32(0xFFFF_FFFF, at: 0x104)

        if !exth.isEmpty {
            var block: [UInt8] = Array("EXTH".utf8)
            var body: [UInt8] = []
            for (type, value) in exth {
                body.append(be32: type)
                body.append(be32: UInt32(value.count + 8))
                body += value
            }
            block.append(be32: UInt32(body.count + 12))
            block.append(be32: UInt32(exth.count))
            block += body
            while block.count % 4 != 0 {
                block.append(0)
            }
            record += block
        }
        let name = Array(fullName.utf8)
        put32(UInt32(record.count), at: 0x54)
        put32(UInt32(name.count), at: 0x58)
        record += name + [0, 0]
        return record
    }

    /// A Palm database holding `records`.
    package static func database(_ records: [[UInt8]]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 78)
        let name = Array("Fixture".utf8)
        bytes.replaceSubrange(0..<name.count, with: name)
        bytes.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
        bytes[76] = UInt8(records.count >> 8)
        bytes[77] = UInt8(records.count & 0xFF)
        var offset = 78 + records.count * 8 + 2
        for (index, record) in records.enumerated() {
            bytes.append(be32: UInt32(offset))
            bytes += [0, 0, 0, UInt8(index & 0xFF)]
            offset += record.count
        }
        bytes += [0, 0]
        for record in records {
            bytes += record
        }
        return Data(bytes)
    }

    /// Overwrites the offset of record `index` in a database, to simulate damage.
    package static func setOffset(_ offset: UInt32, ofRecord index: Int, in data: inout Data) {
        let position = data.startIndex + 78 + index * 8
        for byte in 0..<4 {
            data[position + byte] = UInt8(offset >> (24 - 8 * byte) & 0xFF)
        }
    }

    /// PalmDOC compression: back references of 3 to 10 bytes within 2047
    /// bytes, space-plus-character pairs, and literal runs.
    package static func palmDOC(_ input: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        var position = 0
        func isPlain(_ byte: UInt8) -> Bool {
            byte == 0 || (0x09...0x7F).contains(byte)
        }
        while position < input.count {
            var bestLength = 0
            var bestDistance = 0
            for start in max(0, position - 2047)..<position {
                var length = 0
                while length < 10, position + length < input.count, input[start + length] == input[position + length] {
                    length += 1
                }
                if length > bestLength {
                    bestLength = length
                    bestDistance = position - start
                }
            }
            if bestLength >= 3 {
                let value = 0x8000 | bestDistance << 3 | (bestLength - 3)
                output += [UInt8(value >> 8), UInt8(value & 0xFF)]
                position += bestLength
            } else if input[position] == 0x20, position + 1 < input.count, (0x40...0x7F).contains(input[position + 1]) {
                output.append(input[position + 1] ^ 0x80)
                position += 2
            } else if isPlain(input[position]) {
                output.append(input[position])
                position += 1
            } else {
                var run: [UInt8] = []
                while run.count < 8, position < input.count, !isPlain(input[position]) {
                    run.append(input[position])
                    position += 1
                }
                output.append(UInt8(run.count))
                output += run
            }
        }
        return output
    }

    /// A forward variable-width integer, as in index entries.
    package static func variableWidth(_ value: Int) -> [UInt8] {
        var groups: [UInt8] = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            groups.insert(UInt8(rest & 0x7F), at: 0)
            rest >>= 7
        }
        groups[groups.count - 1] |= 0x80
        return groups
    }

    /// A CNCX record holding `strings`, and the offset of each.
    package static func cncx(_ strings: [String]) -> (record: [UInt8], offsets: [Int]) {
        var record: [UInt8] = []
        var offsets: [Int] = []
        for string in strings {
            offsets.append(record.count)
            let bytes = Array(string.utf8)
            record += variableWidth(bytes.count) + bytes
        }
        record.append(0)
        return (record, offsets)
    }

    /// An INDX index: a header record with a TAGX table, one record of
    /// entries, then `cncx` records. Each tag gets one bit of a single
    /// control byte; an entry's values for a tag must number its
    /// `valuesPerEntry`.
    package static func index(tags: [IndexTag], entries: [(name: String, values: [UInt8: [Int]])], cncx: [[UInt8]] = []) -> [[UInt8]] {
        precondition(tags.count <= 8)
        let headerLength = 0xC0
        func indexHeader(start: Int, count: Int, cncxCount: Int) -> [UInt8] {
            var header: [UInt8] = Array("INDX".utf8)
            let fields = [headerLength, 0, 0, 0, start, count, 65001, 0xFFFF_FFFF, 0, 0, 0, 0, cncxCount]
            for field in fields {
                header.append(be32: UInt32(field))
            }
            return header + [UInt8](repeating: 0, count: headerLength - header.count)
        }

        var main = indexHeader(start: 0, count: 1, cncxCount: cncx.count)
        main += Array("TAGX".utf8)
        main.append(be32: UInt32(12 + 4 * (tags.count + 1)))
        main.append(be32: 1)
        for (bit, tag) in tags.enumerated() {
            main += [tag.tag, UInt8(tag.valuesPerEntry), UInt8(1 << bit), 0]
        }
        main += [0, 0, 0, 1]

        var body: [UInt8] = []
        var positions: [Int] = []
        for entry in entries {
            positions.append(headerLength + body.count)
            let name = Array(entry.name.utf8)
            body.append(UInt8(name.count))
            body += name
            var control: UInt8 = 0
            var values: [UInt8] = []
            for (bit, tag) in tags.enumerated() {
                guard let tagValues = entry.values[tag.tag] else { continue }
                control |= UInt8(1 << bit)
                for value in tagValues {
                    values += variableWidth(value)
                }
            }
            body.append(control)
            body += values
        }
        let idxtStart = headerLength + body.count
        var record = indexHeader(start: idxtStart, count: entries.count, cncxCount: 0) + body
        record += Array("IDXT".utf8)
        for position in positions {
            record += [UInt8(position >> 8), UInt8(position & 0xFF)]
        }
        while record.count % 4 != 0 {
            record.append(0)
        }
        return [main, record] + cncx
    }

    /// An FDST record splitting text at `starts`, the last flow ending at `textLength`.
    package static func fdst(starts: [Int], textLength: Int) -> [UInt8] {
        var record: [UInt8] = Array("FDST".utf8)
        record.append(be32: 12)
        record.append(be32: UInt32(starts.count))
        for (index, start) in starts.enumerated() {
            record.append(be32: UInt32(start))
            record.append(be32: UInt32(index + 1 < starts.count ? starts[index + 1] : textLength))
        }
        return record
    }
}

extension Array where Element == UInt8 {
    fileprivate mutating func append(be32 value: UInt32) {
        append(contentsOf: (0..<4).map { UInt8(value >> (24 - 8 * $0) & 0xFF) })
    }
}
