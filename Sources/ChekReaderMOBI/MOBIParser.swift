import ChekReaderCore
import Foundation

/// Builds a ``Publication`` from a MOBI 6, KF8 or joint MOBI/KF8 file.
///
/// A joint file holds a MOBI 6 book, a `BOUNDARY` record, then a KF8 book
/// whose first record EXTH 121 names. Whatever the file was detected as,
/// the KF8 book is read when there is one, since it keeps the publisher's
/// styling; the MOBI 6 book is read otherwise, or when a joint file's KF8
/// half is damaged.
enum MOBIParser {
    static func parse(_ data: Data, limits: ReaderLimits) throws(ReaderError) -> Publication {
        let database = try PalmDatabase(data, limits: limits)
        let record0 = try database.record(0)
        let header = try MOBIHeader(record: record0)
        try ReaderError.checkCancellation()

        var warnings: [PublicationWarning] = []
        if header.isKF8 {
            return try parseKF8(database, header: header, partStart: 0, record0: record0, mobi6Header: nil, limits: limits)
        }
        if let boundary = header.exth.integer(EXTH.Tag.kf8Boundary),
           let kf8Start = MOBIHeader.record(boundary, partStart: 0, recordCount: database.recordCount),
           kf8Start > 0 {
            do {
                let kf8Header = try MOBIHeader(record: try database.record(kf8Start))
                if kf8Header.isKF8 {
                    return try parseKF8(database, header: kf8Header, partStart: kf8Start, record0: record0, mobi6Header: header, limits: limits)
                }
                warnings.append(PublicationWarning("EXTH 121 names record \(kf8Start) as the KF8 header, but it isn't one; the MOBI 6 version was opened."))
            } catch .malformed(let reason) {
                warnings.append(PublicationWarning("The KF8 version couldn't be read, so the MOBI 6 version was opened: \(reason)"))
            }
        }
        return try parseMOBI6(database, header: header, record0: record0, warnings: warnings, limits: limits)
    }

    // MARK: - MOBI 6

    private static func parseMOBI6(
        _ database: PalmDatabase,
        header: MOBIHeader,
        record0: [UInt8],
        warnings: [PublicationWarning],
        limits: ReaderLimits
    ) throws(ReaderError) -> Publication {
        var warnings = warnings + header.warnings.map { PublicationWarning($0) }
        let text = try MOBIText.read(database, header: header, partStart: 0, limits: limits)
        try ReaderError.checkCancellation()

        // A joint file's MOBI 6 resources end at the KF8 boundary.
        let end = header.exth.integer(EXTH.Tag.kf8Boundary)
            .flatMap { MOBIHeader.record($0, partStart: 0, recordCount: database.recordCount) } ?? database.recordCount
        let resources = try loadResources(database, firstImage: header.firstImageIndex, partStart: 0, end: end, limits: limits)
        warnings += resources.warnings.map { PublicationWarning($0) }
        try ReaderError.checkCancellation()

        var ncx: [MOBI6Content.NCXEntry] = []
        if let index = try ncxIndex(database, header: header, partStart: 0, limits: limits, warnings: &warnings) {
            for entry in index.entries {
                guard let position = entry.value(1) else { continue }
                ncx.append(MOBI6Content.NCXEntry(
                    position: position,
                    title: title(of: entry, in: index, encoding: header.encoding),
                    depth: entry.value(4) ?? 0
                ))
            }
        }

        let metadata = makeMetadata(header, record0: record0)
        let content = try MOBI6Content(
            text: text,
            encoding: header.encoding,
            resources: resources,
            ncx: ncx,
            title: metadata.title,
            language: metadata.languages.first
        )
        warnings += content.warnings
        try ReaderError.checkCancellation()

        var files: [String: Data] = [:]
        var readingOrder: [Link] = []
        for part in content.parts {
            files[part.href] = part.data
            readingOrder.append(Link(href: part.href, mediaType: MOBI6Content.mediaType))
        }
        let resourceLinks = links(for: resources, header: header, files: &files)
        return Publication(
            format: .mobi,
            metadata: metadata,
            readingOrder: readingOrder,
            tableOfContents: content.tableOfContents,
            resources: resourceLinks,
            warnings: warnings,
            container: MemoryContainer(files)
        )
    }

    // MARK: - KF8

    private static func parseKF8(
        _ database: PalmDatabase,
        header: MOBIHeader,
        partStart: Int,
        record0: [UInt8],
        mobi6Header: MOBIHeader?,
        limits: ReaderLimits
    ) throws(ReaderError) -> Publication {
        var warnings = header.warnings.map { PublicationWarning($0) }
        let recordCount = database.recordCount
        guard let skeletonIndex = MOBIHeader.record(header.skeletonIndex, partStart: partStart, recordCount: recordCount),
              let fragmentIndex = MOBIHeader.record(header.fragmentIndex, partStart: partStart, recordCount: recordCount)
        else {
            throw .malformed(reason: "The KF8 header has no skeleton or fragment index.")
        }
        let text = try MOBIText.read(database, header: header, partStart: partStart, limits: limits)
        try ReaderError.checkCancellation()

        let skeletons = try KF8Tables.skeletons(MOBIIndex(database, index: skeletonIndex, limits: limits))
        let fragments = try KF8Tables.fragments(MOBIIndex(database, index: fragmentIndex, limits: limits))
        var fdst: [UInt8]?
        if let index = MOBIHeader.record(header.fdstIndex, partStart: partStart, recordCount: recordCount) {
            fdst = try database.record(index)
        }
        try ReaderError.checkCancellation()

        // KF8 headers in joint files may point at resources before the
        // boundary, or not at all; the MOBI 6 header's index is the fallback.
        var firstImage = MOBIHeader.record(header.firstImageIndex, partStart: partStart, recordCount: recordCount)
        if firstImage == nil, let mobi6Header {
            firstImage = MOBIHeader.record(mobi6Header.firstImageIndex, partStart: 0, recordCount: recordCount)
        }
        let resources = try loadResources(database, first: firstImage, end: recordCount, limits: limits)
        warnings += resources.warnings.map { PublicationWarning($0) }

        var ncx: [KF8Content.NCXEntry] = []
        if let index = try ncxIndex(database, header: header, partStart: partStart, limits: limits, warnings: &warnings) {
            for entry in index.entries {
                guard let fragment = entry.value(6, 0), let offset = entry.value(6, 1) else { continue }
                ncx.append(KF8Content.NCXEntry(
                    fragment: fragment,
                    offset: offset,
                    title: title(of: entry, in: index, encoding: header.encoding),
                    depth: entry.value(4) ?? 0
                ))
            }
        }

        let content = try KF8Content(
            text: text,
            fdst: fdst,
            skeletons: skeletons,
            fragments: fragments,
            ncx: ncx,
            resources: resources,
            limit: Int(clamping: limits.maxUncompressedBytes)
        )
        warnings += content.warnings
        try ReaderError.checkCancellation()

        // A joint file's KF8 header usually repeats the metadata; when it
        // doesn't, the MOBI 6 header's is used.
        var metadataHeader = header
        if header.exth.records.isEmpty, let mobi6Header {
            metadataHeader = mobi6Header
        }
        let metadata = makeMetadata(metadataHeader, record0: record0)

        var files: [String: Data] = [:]
        var readingOrder: [Link] = []
        for part in content.parts {
            files[part.href] = part.data
            readingOrder.append(Link(href: part.href, mediaType: part.mediaType))
        }
        var resourceLinks: [Link] = []
        for flow in content.flowResources {
            files[flow.href] = flow.data
            resourceLinks.append(Link(href: flow.href, mediaType: flow.mediaType))
        }
        resourceLinks += links(for: resources, header: metadataHeader, files: &files)
        return Publication(
            format: .azw3,
            metadata: metadata,
            readingOrder: readingOrder,
            tableOfContents: content.tableOfContents,
            resources: resourceLinks,
            warnings: warnings,
            container: MemoryContainer(files)
        )
    }

    // MARK: - Shared

    private static func loadResources(
        _ database: PalmDatabase,
        firstImage: UInt32,
        partStart: Int,
        end: Int,
        limits: ReaderLimits
    ) throws(ReaderError) -> MOBIResources {
        let first = MOBIHeader.record(firstImage, partStart: partStart, recordCount: database.recordCount)
        return try loadResources(database, first: first, end: end, limits: limits)
    }

    private static func loadResources(_ database: PalmDatabase, first: Int?, end: Int, limits: ReaderLimits) throws(ReaderError) -> MOBIResources {
        guard let first, first > 0 else { return MOBIResources() }
        return try MOBIResources(database, first: first, end: end, limits: limits)
    }

    /// The NCX index, or `nil` with a warning when it's damaged. A book
    /// without a table of contents still reads.
    private static func ncxIndex(
        _ database: PalmDatabase,
        header: MOBIHeader,
        partStart: Int,
        limits: ReaderLimits,
        warnings: inout [PublicationWarning]
    ) throws(ReaderError) -> MOBIIndex? {
        guard let index = MOBIHeader.record(header.ncxIndex, partStart: partStart, recordCount: database.recordCount) else {
            return nil
        }
        do {
            return try MOBIIndex(database, index: index, limits: limits)
        } catch .malformed(let reason) {
            warnings.append(PublicationWarning("The table of contents index couldn't be read: \(reason)"))
            return nil
        }
    }

    /// An NCX entry's label, from the CNCX string tag 3 refers to.
    private static func title(of entry: MOBIIndex.Entry, in index: MOBIIndex, encoding: MOBITextEncoding) -> String {
        guard let offset = entry.value(3), let bytes = index.strings[offset] else {
            return encoding.decode(entry.name)
        }
        return encoding.decode(bytes)
    }

    /// Links for images and fonts, with the EXTH cover marked, adding their
    /// bytes to `files`.
    private static func links(for resources: MOBIResources, header: MOBIHeader, files: inout [String: Data]) -> [Link] {
        // EXTH 201 is the cover's offset from the first image, so it's
        // resource number offset + 1.
        let coverNumber = header.exth.integer(EXTH.Tag.coverOffset).flatMap { offset -> Int? in
            offset == MOBIHeader.null ? nil : Int(offset) + 1
        }
        var links: [Link] = []
        for (number, resource) in resources.byNumber.sorted(by: { $0.key < $1.key }) {
            files[resource.path] = resource.data
            let isCover = number == coverNumber && resource.mediaType.hasPrefix("image/")
            links.append(Link(href: resource.path, mediaType: resource.mediaType, rels: isCover ? ["cover"] : []))
        }
        return links
    }

    private static func makeMetadata(_ header: MOBIHeader, record0: [UInt8]) -> Publication.Metadata {
        let exth = header.exth
        func string(_ bytes: [UInt8]) -> String? {
            let value = header.encoding.decode(bytes).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            return value.isEmpty ? nil : value
        }
        func strings(_ tag: UInt32) -> [String] {
            exth.values(tag).compactMap(string)
        }

        var metadata = Publication.Metadata()
        metadata.title = exth.value(EXTH.Tag.updatedTitle).flatMap(string) ?? string(header.fullName)
        metadata.authors = strings(EXTH.Tag.author).map { Publication.Contributor(name: $0, role: "aut") }
        metadata.publishers = strings(EXTH.Tag.publisher)
        metadata.summary = strings(EXTH.Tag.description).first
        metadata.subjects = strings(EXTH.Tag.subject)
        metadata.published = strings(EXTH.Tag.published).first
        metadata.identifier = strings(EXTH.Tag.isbn).first
            ?? strings(EXTH.Tag.asin).first
            ?? "urn:sha1:" + SHA1.digest(Data(record0)).map { String($0, radix: 16).leftPadded(to: 2) }.joined()
        metadata.languages = strings(EXTH.Tag.language)
        if metadata.languages.isEmpty, let language = MOBILanguage.tag(forLocale: header.locale) {
            metadata.languages = [language]
        }
        switch strings(EXTH.Tag.pageProgressionDirection).first?.lowercased() {
        case "rtl": metadata.readingProgression = .rightToLeft
        case "ltr": metadata.readingProgression = .leftToRight
        default: metadata.readingProgression = .auto
        }
        if strings(EXTH.Tag.fixedLayout).first?.lowercased() == "true" {
            metadata.layout = .fixed
        }
        return metadata
    }
}

extension String {
    /// The string with zeros before it, up to `length` characters.
    fileprivate func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
