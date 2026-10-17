import ChekReaderCore

/// The parts of an EPUB package document (the OPF file) the reader uses.
struct PackageDocument {
    struct Item {
        let id: String
        /// The resolved path from the publication's root.
        let path: String
        let mediaType: String?
        let properties: Set<String>
    }

    struct SpineItem {
        let idref: String
        let isLinear: Bool
        let properties: Set<String>
    }

    var version: String?
    var metadata = Publication.Metadata()
    /// The manifest, in document order.
    var manifest: [Item] = []
    var spine: [SpineItem] = []
    /// The manifest id of the EPUB 2 NCX, from the spine's `toc` attribute.
    var ncxID: String?
    /// The manifest id or path of the cover image, from EPUB 2 metadata.
    var coverReference: String?
    /// EPUB 2 guide references, used as landmarks when there's no nav document.
    var guide: [Link] = []
    var warnings: [PublicationWarning] = []

    func item(id: String) -> Item? {
        manifest.first { $0.id == id }
    }
}

extension PackageDocument {
    /// A `meta` element, either EPUB 3 (`property` and text) or EPUB 2
    /// (`name` and `content`).
    private struct Meta {
        let property: String
        let value: String
        let refines: String?
        let id: String?
        let scheme: String?
    }

    init(_ root: MarkupNode, path: String) throws(ReaderError) {
        guard root.name == "package" else {
            throw .malformed(reason: "\(path) isn't an EPUB package document.")
        }
        version = root.attribute("version")

        let metadataElement = root.firstElement(named: "metadata")
        // EPUB 2 files sometimes wrap Dublin Core in a nested dc-metadata element.
        let entries = metadataElement.map(Self.flatten) ?? []
        let metas = entries.compactMap(Self.meta)
        var refinements: [String: [Meta]] = [:]
        for meta in metas {
            if let refines = meta.refines, refines.hasPrefix("#") {
                refinements[String(refines.dropFirst()), default: []].append(meta)
            }
        }
        let globalMetas = metas.filter { $0.refines == nil }
        func refinement(_ property: String, of element: MarkupNode) -> String? {
            guard let id = element.attribute("id") else { return nil }
            return refinements[id]?.first { $0.property == property }?.value
        }
        func values(_ name: String) -> [MarkupNode] {
            entries.filter { $0.name == name && $0.trimmedText != nil }
        }
        func global(_ property: String) -> [String] {
            globalMetas.filter { $0.property == property }.map(\.value)
        }

        // Identifier: the one named by unique-identifier, else the first.
        let identifiers = values("identifier")
        let uniqueID = root.attribute("unique-identifier")
        metadata.identifier = (identifiers.first { $0.attribute("id") == uniqueID } ?? identifiers.first)?.trimmedText

        // Titles: EPUB 3 can mark which title is main and which is the subtitle.
        let titles = values("title")
        let main = titles.first { refinement("title-type", of: $0) == "main" } ?? titles.first
        metadata.title = main?.trimmedText
        if let main {
            metadata.sortTitle = refinement("file-as", of: main) ?? main.attribute("file-as") ?? global("calibre:title_sort").first
        }
        metadata.subtitle = titles.first { refinement("title-type", of: $0) == "subtitle" }?.trimmedText
        if metadata.title == nil {
            warnings.append(PublicationWarning("The package document has no title.", href: path))
        }

        // Creators default to authors; contributors have no default role.
        for (element, defaultRole) in entries.compactMap({ element -> (MarkupNode, String?)? in
            switch element.name {
            case "creator": (element, "aut")
            case "contributor": (element, nil)
            default: nil
            }
        }) {
            guard let name = element.trimmedText else { continue }
            let role = refinement("role", of: element) ?? element.attribute("role") ?? defaultRole
            let contributor = Publication.Contributor(
                name: name,
                sortAs: refinement("file-as", of: element) ?? element.attribute("file-as"),
                role: role
            )
            if role == "aut" {
                metadata.authors.append(contributor)
            } else {
                metadata.contributors.append(contributor)
            }
        }

        metadata.publishers = values("publisher").compactMap(\.trimmedText)
        metadata.languages = values("language").compactMap(\.trimmedText)
        metadata.subjects = values("subject").compactMap(\.trimmedText)
        metadata.summary = values("description").first?.trimmedText
        let dates = values("date")
        metadata.published = (dates.first { $0.attribute("event") == "publication" } ?? dates.first)?.trimmedText
        metadata.modified = global("dcterms:modified").first

        // Series: EPUB 3 collections, else Calibre's metadata.
        if let collection = globalMetas.first(where: { meta in
            guard meta.property == "belongs-to-collection" else { return false }
            let type = meta.id.flatMap { refinements[$0]?.first { $0.property == "collection-type" }?.value }
            return type == nil || type == "series"
        }) {
            let position = collection.id.flatMap { refinements[$0]?.first { $0.property == "group-position" }?.value }
            metadata.series = Publication.Series(name: collection.value, position: position.flatMap(Double.init))
        } else if let name = global("calibre:series").first {
            metadata.series = Publication.Series(name: name, position: global("calibre:series_index").first.flatMap(Double.init))
        }

        if global("rendition:layout").first == "pre-paginated" {
            metadata.layout = .fixed
        }

        let conformance = global("dcterms:conformsTo")
            + entries.filter { $0.name == "link" && $0.attribute("rel") == "dcterms:conformsTo" }.compactMap { $0.attribute("href") }
        metadata.accessibility = Publication.Accessibility(
            conformsTo: conformance,
            accessModes: global("schema:accessMode"),
            accessModesSufficient: global("schema:accessModeSufficient"),
            features: global("schema:accessibilityFeature"),
            hazards: global("schema:accessibilityHazard"),
            summary: global("schema:accessibilitySummary").first
        )

        coverReference = globalMetas.first { $0.property == "cover" }?.value

        // Manifest.
        for element in root.firstElement(named: "manifest")?.elements(named: "item") ?? [] {
            guard let id = element.attribute("id"), let href = element.attribute("href") else {
                warnings.append(PublicationWarning("A manifest item without an id or href was skipped.", href: path))
                continue
            }
            guard let resolved = EPUBHref.resolve(href, from: path) else {
                warnings.append(PublicationWarning("The manifest item \(id) points outside the publication and was skipped.", href: path))
                continue
            }
            manifest.append(Item(
                id: id,
                path: Link(href: resolved).path,
                mediaType: element.attribute("media-type"),
                properties: Self.tokens(element.attribute("properties"))
            ))
        }

        // Spine.
        let spineElement = root.firstElement(named: "spine")
        ncxID = spineElement?.attribute("toc")
        switch spineElement?.attribute("page-progression-direction") {
        case "rtl": metadata.readingProgression = .rightToLeft
        case "ltr": metadata.readingProgression = .leftToRight
        default: break
        }
        for element in spineElement?.elements(named: "itemref") ?? [] {
            guard let idref = element.attribute("idref") else { continue }
            spine.append(SpineItem(
                idref: idref,
                isLinear: element.attribute("linear") != "no",
                properties: Self.tokens(element.attribute("properties"))
            ))
        }

        // Guide, for EPUB 2 landmarks.
        for element in root.firstElement(named: "guide")?.elements(named: "reference") ?? [] {
            guard let href = element.attribute("href"), let resolved = EPUBHref.resolve(href, from: path) else { continue }
            guide.append(Link(
                href: resolved,
                title: element.attribute("title"),
                rels: Set(element.attribute("type").map { [$0] } ?? [])
            ))
        }
    }

    /// The metadata's children, with nested wrappers such as EPUB 2's
    /// `dc-metadata` and `x-metadata` flattened in place.
    private static func flatten(_ element: MarkupNode) -> [MarkupNode] {
        element.elements.flatMap { child in
            child.name.hasSuffix("-metadata") ? child.elements : [child]
        }
    }

    private static func meta(_ element: MarkupNode) -> Meta? {
        guard element.name == "meta" else { return nil }
        if let property = element.attribute("property") {
            guard let value = element.trimmedText else { return nil }
            return Meta(property: property, value: value, refines: element.attribute("refines"), id: element.attribute("id"), scheme: element.attribute("scheme"))
        }
        if let name = element.attribute("name"), let content = element.attribute("content") {
            return Meta(property: name, value: content, refines: nil, id: nil, scheme: nil)
        }
        return nil
    }

    private static func tokens(_ value: String?) -> Set<String> {
        Set((value ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
    }
}
