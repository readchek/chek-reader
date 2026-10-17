import ChekReaderCore
import Foundation

/// Builds a ``Publication`` from an EPUB's container, package document and
/// navigation.
///
/// Malformed but readable books open in recovery mode: missing pieces are
/// skipped or replaced, and each repair is recorded as a warning.
struct EPUBParser {
    let container: any PublicationContainer
    let limits: ReaderLimits
    /// Whether to read `encryption.xml`. Resource providers return
    /// decrypted resources, so their publications skip it.
    let checksEncryption: Bool
    private var warnings: [PublicationWarning] = []

    init(container: any PublicationContainer, limits: ReaderLimits, checksEncryption: Bool) {
        self.container = container
        self.limits = limits
        self.checksEncryption = checksEncryption
    }

    mutating func parse() async throws(ReaderError) -> Publication {
        let packagePath = try await packageDocumentPath()
        try ReaderError.checkCancellation()

        var obfuscatedFonts: [String: Link.FontObfuscation] = [:]
        if checksEncryption, container.paths?.contains(EPUBEncryption.path) == true {
            let root = try await xml(at: EPUBEncryption.path)
            obfuscatedFonts = try EPUBEncryption.obfuscatedFonts(in: root, paths: container.paths)
        }
        try ReaderError.checkCancellation()

        let document = try PackageDocument(await xml(at: packagePath), path: packagePath)
        warnings += document.warnings
        try ReaderError.checkCancellation()

        let itemsByID = Dictionary(document.manifest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let coverPath = coverImagePath(document, itemsByID: itemsByID)
        let navItem = document.manifest.first { $0.properties.contains("nav") }

        func link(for item: PackageDocument.Item, spine: PackageDocument.SpineItem? = nil) -> Link {
            var rels: Set<String> = []
            if item.path == coverPath {
                rels.insert("cover")
            }
            if item.id == navItem?.id {
                rels.insert("contents")
            }
            var properties = Link.Properties(
                contains: item.properties.subtracting(["nav", "cover-image"]),
                obfuscation: obfuscatedFonts[item.path]
            )
            if let spine {
                properties.page = Self.page(from: spine.properties)
                if spine.properties.contains("rendition:layout-pre-paginated") {
                    properties.layout = .fixed
                } else if spine.properties.contains("rendition:layout-reflowable") {
                    properties.layout = .reflowable
                }
            }
            return Link(href: item.path, mediaType: item.mediaType, rels: rels, properties: properties)
        }

        // Reading order: linear spine items that exist. Non-linear ones, such
        // as answer keys, stay reachable as resources.
        var readingOrder: [Link] = []
        var inReadingOrder: Set<String> = []
        for spineItem in document.spine where spineItem.isLinear {
            guard let item = itemsByID[spineItem.idref] else {
                warnings.append(PublicationWarning("The spine refers to \(spineItem.idref), which isn't in the manifest, so it was skipped.", href: packagePath))
                continue
            }
            guard container.contains(item.path) else {
                warnings.append(PublicationWarning("This chapter is missing from the publication, so it was skipped.", href: item.path))
                continue
            }
            guard !inReadingOrder.contains(item.path) else { continue }
            readingOrder.append(link(for: item, spine: spineItem))
            inReadingOrder.insert(item.path)
        }
        guard !readingOrder.isEmpty else {
            throw .malformed(reason: "The EPUB's spine lists no chapters that exist in the publication.")
        }

        var resources: [Link] = []
        for item in document.manifest where !inReadingOrder.contains(item.path) {
            if !container.contains(item.path) {
                warnings.append(PublicationWarning("This resource is listed in the manifest but missing from the publication.", href: item.path))
            }
            resources.append(link(for: item))
        }

        try ReaderError.checkCancellation()
        var navigation = await readNavigation(document, navItem: navItem, itemsByID: itemsByID)
        if navigation.landmarks.isEmpty {
            navigation.landmarks = document.guide
        }

        return Publication(
            format: .epub,
            metadata: document.metadata,
            readingOrder: readingOrder,
            tableOfContents: navigation.tableOfContents,
            pageList: navigation.pageList,
            landmarks: navigation.landmarks,
            resources: resources,
            warnings: warnings,
            container: container
        )
    }

    /// The package document's path, from `META-INF/container.xml`, or the
    /// only `.opf` file when the container document is missing or broken.
    private mutating func packageDocumentPath() async throws(ReaderError) -> String {
        let containerPath = "META-INF/container.xml"
        if container.contains(containerPath) {
            do {
                let root = try await xml(at: containerPath)
                let rootfiles = root.descendants(named: "rootfile")
                let rootfile = rootfiles.first { $0.attribute("media-type") == "application/oebps-package+xml" } ?? rootfiles.first
                if let fullPath = rootfile?.attribute("full-path"),
                   let path = EPUBHref.resolve(fullPath, from: ""),
                   container.contains(path) {
                    return path
                }
                warnings.append(PublicationWarning("The container document doesn't name a package document that exists.", href: containerPath))
            } catch .limitExceeded(let limit) {
                throw .limitExceeded(limit)
            } catch .cancelled {
                throw .cancelled
            } catch {
                warnings.append(PublicationWarning("The container document couldn't be read: \(error.localizedDescription)", href: containerPath))
            }
        } else {
            warnings.append(PublicationWarning("The publication has no META-INF/container.xml.", href: containerPath))
        }

        guard let paths = container.paths,
              let path = paths.filter({ $0.lowercased().hasSuffix(".opf") }).sorted().first
        else {
            throw .malformed(reason: "The EPUB's package document can't be found. Check that META-INF/container.xml exists and names it.")
        }
        warnings.append(PublicationWarning("Using \(path) as the package document.", href: path))
        return path
    }

    private func xml(at path: String) async throws(ReaderError) -> MarkupNode {
        try XMLTree.parse(await container.data(at: path), limits: limits)
    }

    /// The table of contents, page list and landmarks: from the EPUB 3 nav
    /// document, falling back to the EPUB 2 NCX for anything it lacks.
    private mutating func readNavigation(
        _ document: PackageDocument,
        navItem: PackageDocument.Item?,
        itemsByID: [String: PackageDocument.Item]
    ) async -> EPUBNavigation {
        var navigation = EPUBNavigation()
        if let navItem {
            do {
                navigation = try EPUBNavigation(navDocument: await xml(at: navItem.path), path: navItem.path)
            } catch {
                warnings.append(PublicationWarning("The navigation document couldn't be read: \(error.localizedDescription)", href: navItem.path))
            }
        }
        guard navigation.tableOfContents.isEmpty || navigation.pageList.isEmpty else {
            return navigation
        }

        let ncxItem = document.ncxID.flatMap { itemsByID[$0] }
            ?? document.manifest.first { $0.mediaType == "application/x-dtbncx+xml" }
        if let ncxItem, container.contains(ncxItem.path) {
            do {
                let ncx = try EPUBNavigation(ncx: await xml(at: ncxItem.path), path: ncxItem.path)
                if navigation.tableOfContents.isEmpty {
                    navigation.tableOfContents = ncx.tableOfContents
                }
                if navigation.pageList.isEmpty {
                    navigation.pageList = ncx.pageList
                }
            } catch {
                warnings.append(PublicationWarning("The NCX couldn't be read: \(error.localizedDescription)", href: ncxItem.path))
            }
        }
        if navigation.tableOfContents.isEmpty {
            warnings.append(PublicationWarning("The publication has no table of contents."))
        }
        return navigation
    }

    /// The cover image's path: the EPUB 3 `cover-image` item, else the item
    /// the EPUB 2 `cover` meta names by id or, in some books, by path.
    private func coverImagePath(_ document: PackageDocument, itemsByID: [String: PackageDocument.Item]) -> String? {
        if let item = document.manifest.first(where: { $0.properties.contains("cover-image") }) {
            return item.path
        }
        guard let reference = document.coverReference else { return nil }
        if let item = itemsByID[reference] {
            return item.path
        }
        return document.manifest.first { $0.path.hasSuffix(reference) }?.path
    }

    private static func page(from properties: Set<String>) -> Link.Page? {
        if properties.contains("page-spread-left") || properties.contains("rendition:page-spread-left") {
            return .left
        }
        if properties.contains("page-spread-right") || properties.contains("rendition:page-spread-right") {
            return .right
        }
        if properties.contains("rendition:page-spread-center") || properties.contains("page-spread-center") {
            return .center
        }
        return nil
    }
}

extension EPUBNavigation {
    init() {}
}
