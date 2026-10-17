import ChekReaderCore

/// Converts between locators and PDF pages.
enum PDFPageLocation {
    /// The 0-based page a locator points at: its `page=N` fragment, or else
    /// its progression through the document. `nil` for an empty document.
    static func pageIndex(of locator: Locator, pageCount: Int) -> Int? {
        guard pageCount > 0 else { return nil }
        for fragment in locator.locations.fragments {
            if let page = Self.page(inFragment: fragment) {
                return min(max(page - 1, 0), pageCount - 1)
            }
        }
        let progression = locator.locations.progression ?? 0
        guard progression.isFinite else { return 0 }
        return min(max(Int((progression * Double(pageCount)).rounded()), 0), pageCount - 1)
    }

    /// The 1-based page in a fragment such as `page=12`, which may carry
    /// other parameters after an `&`.
    static func page(inFragment fragment: some StringProtocol) -> Int? {
        for parameter in fragment.split(separator: "&") where parameter.hasPrefix("page=") {
            if let page = Int(parameter.dropFirst(5)), page > 0 {
                return page
            }
        }
        return nil
    }

    /// Every titled table of contents entry with its 0-based page, in page
    /// order, so the title for a page is the last entry at or before it.
    static func titles(in links: [Link]) -> [(page: Int, title: String)] {
        var found: [(page: Int, title: String)] = []
        func visit(_ links: [Link]) {
            for link in links {
                if let title = link.title, let hash = link.href.firstIndex(of: "#"),
                   let page = Self.page(inFragment: link.href[link.href.index(after: hash)...]) {
                    found.append((page - 1, title))
                }
                visit(link.children)
            }
        }
        visit(links)
        // Stable, so entries on the same page keep their outline order.
        return found.enumerated().sorted { ($0.element.page, $0.offset) < ($1.element.page, $1.offset) }.map(\.element)
    }
}
