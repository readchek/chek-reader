public import Foundation

extension Publication {
    /// How much text on each side of a match is kept, matching the anchors
    /// the reader script keeps.
    package static let searchContextLength = 32

    /// Finds `query` in the publication's text.
    ///
    /// Each result is a ``Locator`` for the resource holding the match, with
    /// the matched text in ``Locator/Text/highlight`` and some text around it
    /// in ``Locator/Text/before`` and ``Locator/Text/after``, in reading
    /// order. `ReaderController.go(to:)` opens the page holding the match.
    /// Comics have no text, so they find nothing.
    ///
    /// Reflowable formats are searched from their markup, so every chapter
    /// is read; call this off the critical path. A format whose text the
    /// core can't read, such as PDF, searches through its module.
    public func search(for query: String, options: SearchOptions = SearchOptions()) async throws(ReaderError) -> [Locator] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, options.limit > 0 else { return [] }
        if let module = try? ReaderFormats.module(for: format),
           let found = try await module.search(self, for: query, options: options) {
            return found
        }
        return try await searchMarkup(for: query, options: options)
    }

    /// Searches every HTML resource in the reading order.
    private func searchMarkup(for query: String, options: SearchOptions) async throws(ReaderError) -> [Locator] {
        var found: [Locator] = []
        for link in readingOrder where MediaType.isHTML(link.mediaType ?? MediaType.forPath(link.path)) {
            try ReaderError.checkCancellation()
            let data = try await data(at: link.path)
            let text = HTMLText.flatten(Self.decode(data))
            guard let resource = locator(for: Link(href: link.path)) else { continue }
            Self.find(query, in: text, options: options, resource: resource, into: &found)
            if found.count >= options.limit {
                return Array(found.prefix(options.limit))
            }
        }
        return found
    }

    /// Every match in `text`, as locators into `resource`.
    package static func find(_ query: String, in text: String, options: SearchOptions, resource: Locator, into found: inout [Locator]) {
        let context = searchContextLength
        let total = Double(max(text.count, 1))
        var searched = text.startIndex
        var cursor = text.startIndex
        var offset = 0
        while found.count < options.limit,
              let range = text.range(of: query, options: options.compareOptions, range: searched..<text.endIndex),
              !range.isEmpty {
            offset += text.distance(from: cursor, to: range.lowerBound)
            cursor = range.lowerBound
            let before = text.index(range.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
            let after = text.index(range.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex
            var locator = resource
            locator.locations.fragments = []
            locator.locations.progression = Double(offset) / total
            locator.text = Locator.Text(
                before: String(text[before..<range.lowerBound]),
                highlight: String(text[range]),
                after: String(text[range.upperBound..<after])
            )
            found.append(locator)
            searched = range.upperBound
        }
    }

    /// The document's text: UTF-8, or Latin-1 for the odd HTML file that
    /// isn't, since every byte is a character in it.
    private static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }
}
