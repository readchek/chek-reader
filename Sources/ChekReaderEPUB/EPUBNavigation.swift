import ChekReaderCore

/// Navigation parsed from an EPUB 3 nav document or an EPUB 2 NCX.
struct EPUBNavigation {
    var tableOfContents: [Link] = []
    var pageList: [Link] = []
    var landmarks: [Link] = []

    /// Reads the `nav` elements of an EPUB 3 navigation document at `path`.
    init(navDocument root: XMLNode, path: String) {
        for nav in root.descendants(named: "nav") {
            let types = Self.types(of: nav)
            guard let list = nav.firstDescendant(named: "ol") else { continue }
            let links = Self.listItems(in: list, base: path)
            if types.contains("toc"), tableOfContents.isEmpty {
                tableOfContents = links
            } else if types.contains("page-list"), pageList.isEmpty {
                pageList = links
            } else if types.contains("landmarks"), landmarks.isEmpty {
                landmarks = links
            }
        }
    }

    /// Reads the navigation map and page list of an EPUB 2 NCX at `path`.
    init(ncx root: XMLNode, path: String) {
        if let navMap = root.firstElement(named: "navMap") {
            tableOfContents = Self.navPoints(in: navMap, named: "navPoint", base: path)
        }
        if let pages = root.firstElement(named: "pageList") {
            pageList = Self.navPoints(in: pages, named: "pageTarget", base: path)
        }
    }

    private static func types(of element: XMLNode) -> Set<String> {
        // `epub:type`, matched by local name.
        Set((element.attribute("type") ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// The links in an `ol`. An entry without its own href, such as a
    /// heading in a `span`, takes the href of its first child.
    private static func listItems(in list: XMLNode, base: String) -> [Link] {
        list.elements(named: "li").compactMap { item -> Link? in
            let label = item.firstElement(named: "a") ?? item.firstElement(named: "span")
            let children = item.firstElement(named: "ol").map { listItems(in: $0, base: base) } ?? []
            let href = label?.attribute("href").flatMap { EPUBHref.resolve($0, from: base) } ?? children.first?.href
            guard let href else { return nil }
            let title = label?.trimmedText ?? label?.attribute("title")
            return Link(href: href, title: title, rels: label.map { types(of: $0) } ?? [], children: children)
        }
    }

    private static func navPoints(in element: XMLNode, named name: String, base: String) -> [Link] {
        element.elements(named: name).compactMap { point -> Link? in
            let children = navPoints(in: point, named: name, base: base)
            let source = point.firstElement(named: "content")?.attribute("src")
            guard let href = source.flatMap({ EPUBHref.resolve($0, from: base) }) ?? children.first?.href else {
                return nil
            }
            let title = point.firstElement(named: "navLabel")?.firstElement(named: "text")?.trimmedText
            return Link(href: href, title: title, children: children)
        }
    }
}
