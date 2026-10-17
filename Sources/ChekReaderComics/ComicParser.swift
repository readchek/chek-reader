import ChekReaderCore
import Foundation

/// Builds a ``Publication`` from the images in a comic archive.
///
/// Pages are the archive's images in natural order, so `page 2` comes
/// before `page 10`. `ComicInfo.xml` supplies metadata, the cover and
/// bookmarks when the archive has one.
struct ComicParser {
    let container: any PublicationContainer
    let format: ReaderFormat
    let limits: ReaderLimits
    /// The file name, for a title when the comic has no metadata.
    let fileName: String?

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "heif", "jxl", "bmp", "tif", "tiff",
    ]

    func parse() async throws(ReaderError) -> Publication {
        let paths = container.paths ?? []
        let pages = paths.filter(Self.isPage).sorted { NaturalOrder.precedes($0, $1) }
        guard !pages.isEmpty else {
            throw .malformed(reason: "The comic has no page images. Check that the archive holds JPEG, PNG, GIF, WebP, AVIF or HEIC files.")
        }

        var warnings: [PublicationWarning] = []
        var info = ComicInfo()
        if let infoPath = paths.filter({ ($0.split(separator: "/").last ?? "").lowercased() == "comicinfo.xml" })
            .min(by: { $0.count < $1.count }) {
            do {
                info = try ComicInfo(XMLTree.parse(await container.data(at: infoPath), limits: limits))
            } catch .cancelled {
                throw .cancelled
            } catch .limitExceeded(let limit) {
                throw .limitExceeded(limit)
            } catch {
                warnings.append(PublicationWarning("ComicInfo.xml couldn't be read, so the comic has no metadata: \(error.localizedDescription)", href: infoPath))
            }
        }
        try ReaderError.checkCancellation()

        var metadata = info.metadata
        if metadata.title == nil, let fileName {
            metadata.title = Self.title(fromFileName: fileName)
        }
        let coverIndex = info.coverPage.flatMap { pages.indices.contains($0) ? $0 : nil } ?? 0
        let readingOrder = pages.enumerated().map { index, path in
            Link(href: path, mediaType: MediaType.forPath(path), rels: index == coverIndex ? ["cover"] : [])
        }

        return Publication(
            format: format,
            metadata: metadata,
            readingOrder: readingOrder,
            tableOfContents: Self.tableOfContents(pages: pages, bookmarks: info.bookmarks),
            warnings: warnings,
            container: container
        )
    }

    /// A publication for pages an app streams one at a time.
    static func parse(pages source: any PageSource, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        let count: Int
        do {
            count = try await source.pageCount()
        } catch let error as ReaderError {
            throw error
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .network(reason: "The page source couldn't say how many pages it has: \(error.localizedDescription)")
        }
        guard count > 0 else {
            throw .malformed(reason: "The page source has no pages.")
        }
        guard count <= limits.maxArchiveEntries else {
            throw .limitExceeded(.archiveEntries)
        }
        // The pages' types aren't known until they're read, and ImageIO
        // works them out from the bytes.
        let readingOrder = (0..<count).map { index in
            Link(href: PageSourceContainer.href(forPage: index), rels: index == 0 ? ["cover"] : [])
        }
        return Publication(
            format: .cbz,
            metadata: Publication.Metadata(layout: .fixed),
            readingOrder: readingOrder,
            container: PageSourceContainer(source: source, pageCount: count, limits: limits)
        )
    }

    static func isPage(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        // macOS resource forks and hidden files aren't pages.
        guard let name = components.last, !components.contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" }) else {
            return false
        }
        guard let dot = name.lastIndex(of: ".") else { return false }
        return imageExtensions.contains(name[name.index(after: dot)...].lowercased())
    }

    /// Bookmarks when the comic has them, else one entry per folder when
    /// the pages are split into folders, as chapter collections often are.
    static func tableOfContents(pages: [String], bookmarks: [(page: Int, title: String)]) -> [Link] {
        let marked = bookmarks.filter { pages.indices.contains($0.page) }
        if !marked.isEmpty {
            return marked.sorted { $0.page < $1.page }.map { Link(href: pages[$0.page], title: $0.title) }
        }
        var entries: [Link] = []
        var lastFolder: Substring?
        for page in pages {
            let folder = page.split(separator: "/").dropLast().last
            guard let folder, folder != lastFolder else { continue }
            lastFolder = folder
            entries.append(Link(href: page, title: String(folder)))
        }
        return entries.count > 1 ? entries : []
    }

    static func title(fromFileName fileName: String) -> String? {
        var name = fileName
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            name = String(name[..<dot])
        }
        let title = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}

/// Orders paths as people expect, comparing runs of digits by value.
enum NaturalOrder {
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        var left = Array(lhs.lowercased().unicodeScalars)[...]
        var right = Array(rhs.lowercased().unicodeScalars)[...]
        while let l = left.first, let r = right.first {
            if ("0"..."9").contains(l), ("0"..."9").contains(r),
               let leftNumber = digits(&left), let rightNumber = digits(&right) {
                if leftNumber != rightNumber {
                    return leftNumber.precedes(rightNumber)
                }
                continue
            }
            if l != r {
                return l.value < r.value
            }
            left = left.dropFirst()
            right = right.dropFirst()
        }
        if left.isEmpty != right.isEmpty {
            return left.isEmpty
        }
        // Equal ignoring case and leading zeros: fall back to the exact text.
        return lhs < rhs
    }

    /// A run of ASCII digits as its significant digits, so numbers of any
    /// length compare without overflowing.
    private struct Number: Equatable {
        var digits: Substring

        func precedes(_ other: Number) -> Bool {
            digits.count != other.digits.count ? digits.count < other.digits.count : digits < other.digits
        }
    }

    private static func digits(_ scalars: inout ArraySlice<Unicode.Scalar>) -> Number? {
        var text = ""
        while let scalar = scalars.first, ("0"..."9").contains(scalar) {
            text.unicodeScalars.append(scalar)
            scalars = scalars.dropFirst()
        }
        guard !text.isEmpty else { return nil }
        let significant = text.drop { $0 == "0" }
        return Number(digits: significant.isEmpty ? "0" : significant)
    }
}
