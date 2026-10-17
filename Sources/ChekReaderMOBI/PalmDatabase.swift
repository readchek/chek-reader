import ChekReaderCore
import Foundation

/// The Palm database every MOBI and AZW3 file is: a 78-byte header, then a
/// list of records, each running to the start of the next.
struct PalmDatabase: Sendable {
    /// The header's length; the record list follows it.
    static let headerLength = 78
    /// Each record list entry is an offset, attributes and a unique ID.
    static let recordEntryLength = 8

    private let data: Data
    /// Where each record starts and ends, relative to the file's start.
    private let ranges: [Range<Int>]

    /// The database's type and creator, such as `BOOK` and `MOBI`.
    let typeAndCreator: String

    var recordCount: Int { ranges.count }

    init(_ data: Data, limits: ReaderLimits) throws(ReaderError) {
        guard data.count >= Self.headerLength else {
            throw .malformed(reason: "The file is too short to be a MOBI book.")
        }
        self.data = data
        let header = BigEndianBytes([UInt8](data.prefix(Self.headerLength)), name: "Palm database header")
        typeAndCreator = String(decoding: try header.bytes(at: 60, count: 8), as: UTF8.self)
        let count = Int(try header.uint16(at: 76))
        guard count > 0 else {
            throw .malformed(reason: "The MOBI file has no records.")
        }
        guard count <= limits.maxArchiveEntries else {
            throw .limitExceeded(.archiveEntries)
        }
        let listEnd = Self.headerLength + count * Self.recordEntryLength
        guard listEnd <= data.count else {
            throw .malformed(reason: "The MOBI file's record list runs past the end of the file. The file may be truncated.")
        }
        let list = BigEndianBytes(
            [UInt8](data[data.startIndex + Self.headerLength..<data.startIndex + listEnd]),
            name: "record list"
        )
        var offsets: [Int] = []
        offsets.reserveCapacity(count)
        for index in 0..<count {
            offsets.append(Int(try list.uint32(at: index * Self.recordEntryLength)))
        }
        // Records are contiguous, so offsets must ascend from the end of the
        // list to the end of the file. Anything else means a damaged or
        // hostile file, and reading it would overlap or overrun.
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(count)
        for index in 0..<count {
            let start = offsets[index]
            let end = index + 1 < count ? offsets[index + 1] : data.count
            guard start >= listEnd, start <= end, end <= data.count else {
                throw .malformed(reason: "The MOBI file's record \(index) has an offset outside the file or out of order. The file may be damaged.")
            }
            ranges.append(start..<end)
        }
        self.ranges = ranges
    }

    /// The bytes of record `index`.
    func record(_ index: Int) throws(ReaderError) -> [UInt8] {
        guard index >= 0, index < ranges.count else {
            throw .malformed(reason: "The MOBI file refers to record \(index), but it has only \(ranges.count) records.")
        }
        let range = ranges[index]
        return [UInt8](data[data.startIndex + range.lowerBound..<data.startIndex + range.upperBound])
    }

    /// The first `count` bytes of record `index`, or fewer if it's shorter,
    /// for checking a record's signature without copying all of it.
    func prefix(ofRecord index: Int, count: Int) -> [UInt8] {
        guard index >= 0, index < ranges.count else { return [] }
        let range = ranges[index]
        let end = min(range.upperBound, range.lowerBound + count)
        return [UInt8](data[data.startIndex + range.lowerBound..<data.startIndex + end])
    }

    /// The length of record `index`, or 0 when there's no such record.
    func length(ofRecord index: Int) -> Int {
        guard index >= 0, index < ranges.count else { return 0 }
        return ranges[index].count
    }
}
