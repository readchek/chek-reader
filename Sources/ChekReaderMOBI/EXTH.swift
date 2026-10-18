/// The EXTH block after the MOBI header: typed metadata records such as
/// the author, publisher and cover.
struct EXTH: Sendable {
    /// Record types this package reads.
    enum Tag {
        static let author: UInt32 = 100
        static let publisher: UInt32 = 101
        static let description: UInt32 = 103
        static let isbn: UInt32 = 104
        static let subject: UInt32 = 105
        static let published: UInt32 = 106
        static let asin: UInt32 = 113
        static let kf8Boundary: UInt32 = 121
        static let fixedLayout: UInt32 = 122
        static let coverOffset: UInt32 = 201
        static let updatedTitle: UInt32 = 503
        static let language: UInt32 = 524
        static let pageProgressionDirection: UInt32 = 527
    }

    struct Record: Sendable {
        let type: UInt32
        let data: [UInt8]
    }

    private(set) var records: [Record] = []
    private(set) var warnings: [String] = []

    init() {}

    /// Reads the block at `offset`. A damaged block keeps the records read
    /// before the damage, since metadata is never needed to read the text.
    init(_ bytes: BigEndianBytes, at offset: Int) {
        guard bytes.has("EXTH", at: offset),
              let length = bytes.optionalUInt32(at: offset + 4),
              let count = bytes.optionalUInt32(at: offset + 8)
        else {
            warnings.append("The MOBI header says it has EXTH metadata, but there is none.")
            return
        }
        // The block can't extend past the record, whatever its length says.
        let end = min(bytes.count, offset + Int(length))
        var position = offset + 12
        for _ in 0..<min(Int(count), bytes.count / 8) {
            guard position + 8 <= end,
                  let type = bytes.optionalUInt32(at: position),
                  let recordLength = bytes.optionalUInt32(at: position + 4).map({ Int($0) }),
                  recordLength >= 8, recordLength <= end - position
            else {
                warnings.append("The EXTH metadata is damaged; some metadata may be missing.")
                return
            }
            records.append(Record(type: type, data: Array(bytes.bytes[position + 8..<position + recordLength])))
            position += recordLength
        }
    }

    /// Every value of `type`, in file order.
    func values(_ type: UInt32) -> [[UInt8]] {
        records.filter { $0.type == type }.map(\.data)
    }

    /// The first value of `type`.
    func value(_ type: UInt32) -> [UInt8]? {
        records.first { $0.type == type }?.data
    }

    /// The first value of `type` as a big-endian integer, for numeric records.
    func integer(_ type: UInt32) -> UInt32? {
        guard let data = value(type), data.count == 4 else { return nil }
        return data.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
