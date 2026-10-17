import ChekReaderCore

/// The headers in the first record of a MOBI 6 or KF8 part: the PalmDOC
/// header, the MOBI header and the optional EXTH metadata.
///
/// Record indices in the header are relative to the part's first record,
/// so a combined file's KF8 part refers to its own records the same way a
/// standalone AZW3 does.
struct MOBIHeader: Sendable {
    /// How text records are compressed.
    enum Compression: Sendable, Equatable {
        case none
        case palmDOC
        case huffCDIC
    }

    /// The value in index fields that means "none".
    static let null: UInt32 = 0xFFFF_FFFF

    let compression: Compression
    /// The length of the uncompressed text, as the header records it.
    let textLength: Int
    let textRecordCount: Int
    let encoding: MOBITextEncoding
    /// The MOBI format version: 8 for KF8, 6 or lower for MOBI 6.
    let version: UInt32
    let uniqueID: UInt32
    let fullName: [UInt8]
    let locale: UInt32
    /// Which kinds of trailing entries follow the text in each text record.
    let extraDataFlags: UInt16

    // Raw record indices, relative to the part's first record. ``null`` when absent.
    let firstImageIndex: UInt32
    let huffRecordIndex: UInt32
    let huffRecordCount: UInt32
    let ncxIndex: UInt32
    let fdstIndex: UInt32
    let skeletonIndex: UInt32
    let fragmentIndex: UInt32

    let exth: EXTH
    /// Problems found while reading the headers that didn't stop them being read.
    let warnings: [String]

    var isKF8: Bool { version >= 8 }

    init(record: [UInt8]) throws(ReaderError) {
        let bytes = BigEndianBytes(record, name: "header record")
        switch try bytes.uint16(at: 0) {
        case 1: compression = .none
        case 2: compression = .palmDOC
        case 17480: compression = .huffCDIC
        case let other:
            throw .malformed(reason: "The MOBI file uses compression type \(other), which isn't a MOBI compression.")
        }
        textLength = Int(try bytes.uint32(at: 4))
        textRecordCount = Int(try bytes.uint16(at: 8))
        // Mobipocket DRM is the only encryption MOBI defines. Apps that have
        // a key decrypt the book before handing it over.
        guard try bytes.uint16(at: 12) == 0 else {
            throw .drmProtected(scheme: "Mobipocket DRM")
        }
        guard bytes.has("MOBI", at: 16) else {
            throw .malformed(reason: "The MOBI file has no MOBI header.")
        }
        let headerLength = Int(try bytes.uint32(at: 20))
        // The fields every version has end 0x18 bytes into the header. Later
        // fields are read only when both the header and the record cover them.
        guard headerLength >= 0x18 else {
            throw .malformed(reason: "The MOBI header's length is \(headerLength), too short for a MOBI header.")
        }
        var warnings: [String] = []

        switch try bytes.uint32(at: 28) {
        case 65001: encoding = .utf8
        case 1252: encoding = .cp1252
        case let other:
            encoding = .cp1252
            warnings.append("The MOBI header names text encoding \(other); reading the text as Windows-1252.")
        }
        uniqueID = try bytes.uint32(at: 32)
        let version = try bytes.uint32(at: 36)
        self.version = version

        // Fields past the declared header length belong to something else,
        // such as the EXTH block, so they're only read when the header covers them.
        let headerEnd = 16 + headerLength
        func field(_ offset: Int) -> UInt32 {
            guard offset + 4 <= headerEnd else { return Self.null }
            return bytes.optionalUInt32(at: offset) ?? Self.null
        }

        let nameOffset = Int(field(0x54))
        let nameLength = Int(field(0x58))
        if nameLength > 0, bytes.contains(nameOffset, nameLength) {
            fullName = try bytes.bytes(at: nameOffset, count: nameLength)
        } else {
            fullName = []
        }
        locale = field(0x5C)
        firstImageIndex = field(0x6C)
        huffRecordIndex = field(0x70)
        huffRecordCount = field(0x74)
        let exthFlags = field(0x80)

        // KindleUnpack reads the trailing entry flags only from headers at
        // least 0xE4 long, and only from version 5 on; older files have
        // other data there.
        if headerLength >= 0xE4, version >= 5, bytes.contains(0xF2, 2) {
            extraDataFlags = try bytes.uint16(at: 0xF2)
        } else {
            extraDataFlags = 0
        }
        ncxIndex = field(0xF4)
        if version >= 8 {
            fdstIndex = field(0xC0)
            fragmentIndex = field(0xF8)
            skeletonIndex = field(0xFC)
        } else {
            fdstIndex = Self.null
            fragmentIndex = Self.null
            skeletonIndex = Self.null
        }

        if exthFlags != Self.null, exthFlags & 0x40 != 0 {
            let parsed = EXTH(bytes, at: headerEnd)
            warnings += parsed.warnings
            exth = parsed
        } else {
            exth = EXTH()
        }
        self.warnings = warnings
    }

    /// The absolute record index for a raw index field, or `nil` when the
    /// field is ``null`` or points outside the database.
    ///
    /// Joint files sometimes store indices that point before the KF8 part
    /// as negative numbers in 32 bits, so the addition wraps the way the
    /// writer's subtraction did.
    static func record(_ raw: UInt32, partStart: Int, recordCount: Int) -> Int? {
        guard raw != null else { return nil }
        let absolute = Int(UInt32(truncatingIfNeeded: partStart) &+ raw)
        guard absolute < recordCount else { return nil }
        return absolute
    }
}
