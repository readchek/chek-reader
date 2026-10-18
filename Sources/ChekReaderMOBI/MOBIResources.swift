import ChekReaderCore
import Foundation

/// The images and fonts stored after a part's text, numbered from 1 at the
/// header's first image index, the way `recindex` and `kindle:embed`
/// refer to them.
struct MOBIResources: Sendable {
    struct Resource: Sendable {
        let path: String
        let mediaType: String
        let data: Data
    }

    /// Records that mark the end of the resources or hold other data.
    /// Calibre and KindleUnpack skip these rather than stop at them, since
    /// some writers put a `RESC` or `FDST` record among the images.
    private static let skippedSignatures = ["FLIS", "FCIS", "SRCS", "FDST", "DATP", "AUDI", "VIDE", "RESC", "CMET", "PAGE", "CRES", "CONT", "kind"]
    /// The record every Palm database book ends with.
    private static let endOfFile: [UInt8] = [0xE9, 0x8E, 0x0D, 0x0A]

    private(set) var byNumber: [Int: Resource] = [:]
    private(set) var warnings: [String] = []

    init() {}

    /// Reads resources from record `first` until the end-of-file record, a
    /// joint file's boundary record or `end`.
    init(_ database: PalmDatabase, first: Int, end: Int, limits: ReaderLimits) throws(ReaderError) {
        guard first < end else { return }
        for index in first..<end {
            try ReaderError.checkCancellation()
            let number = index - first + 1
            let signature = database.prefix(ofRecord: index, count: 4)
            if signature == Self.endOfFile || signature.hasSignature("BOUN") {
                break
            }
            if Self.skippedSignatures.contains(where: { signature.hasSignature($0) }) || signature.isEmpty {
                continue
            }
            let record = try database.record(index)
            guard Int64(record.count) <= limits.maxResourceBytes else {
                throw .limitExceeded(.resourceBytes)
            }
            if record.hasSignature("FONT") {
                do {
                    let font = try MOBIFont.decode(record, limits: limits)
                    let path = "fonts/\(Self.name(number)).\(font.fileExtension)"
                    byNumber[number] = Resource(path: path, mediaType: font.mediaType, data: Data(font.data))
                } catch .malformed(let reason) {
                    warnings.append("Font record \(index) was skipped: \(reason)")
                }
                continue
            }
            if let type = ImageType(sniffing: record) {
                let path = "images/\(Self.name(number)).\(type.fileExtension)"
                byNumber[number] = Resource(path: path, mediaType: type.mediaType, data: Data(record))
            }
            // Anything else, such as a placeholder or an unknown record,
            // keeps its number but isn't served.
        }
    }

    /// The path of image or font `number`, 1-based from the first image index.
    func path(_ number: Int) -> String? {
        byNumber[number]?.path
    }

    /// Every resource, in record order.
    var all: [Resource] {
        byNumber.keys.sorted().compactMap { byNumber[$0] }
    }

    /// `number` padded to four digits, as KindleUnpack names resources.
    static func name(_ number: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}
