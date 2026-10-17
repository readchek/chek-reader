import ChekReaderCore
import Foundation

/// Reads a FictionBook's `<description>`.
enum FB2Metadata {
    /// The publication's metadata, and the id of the binary its cover page
    /// shows, if it has one.
    static func read(_ root: MarkupNode) -> (metadata: Publication.Metadata, coverID: String?) {
        var metadata = Publication.Metadata(readingProgression: .auto, layout: .reflowable)
        guard let description = root.firstElement(named: "description") else {
            return (metadata, nil)
        }
        var coverID: String?

        if let titleInfo = description.firstElement(named: "title-info") {
            metadata.title = titleInfo.firstElement(named: "book-title")?.trimmedText
            metadata.authors = titleInfo.elements(named: "author").compactMap { contributor($0, role: "aut") }
            metadata.contributors = titleInfo.elements(named: "translator").compactMap { contributor($0, role: "trl") }
            metadata.subjects = titleInfo.elements(named: "genre").compactMap(\.trimmedText)
            metadata.languages = titleInfo.elements(named: "lang").compactMap(\.trimmedText)
            metadata.summary = titleInfo.firstElement(named: "annotation").flatMap(plainSummary)
            if let sequence = titleInfo.firstElement(named: "sequence"),
               let name = sequence.attribute("name").flatMap(collapsed) {
                metadata.series = Publication.Series(
                    name: name,
                    position: sequence.attribute("number").flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                )
            }
            if let date = titleInfo.firstElement(named: "date") {
                // `value` is the machine-readable date; the text is for people.
                metadata.published = date.attribute("value").flatMap(collapsed) ?? date.trimmedText
            }
            if let image = titleInfo.firstElement(named: "coverpage")?.firstElement(named: "image"),
               let href = image.attribute("href"), !href.isEmpty {
                coverID = href.hasPrefix("#") ? String(href.dropFirst()) : href
            }
        }

        metadata.identifier = description.firstElement(named: "document-info")?.firstElement(named: "id")?.trimmedText

        if let publishInfo = description.firstElement(named: "publish-info") {
            metadata.publishers = publishInfo.elements(named: "publisher").compactMap(\.trimmedText)
            if metadata.published == nil {
                metadata.published = publishInfo.firstElement(named: "year")?.trimmedText
            }
            if metadata.identifier == nil {
                metadata.identifier = publishInfo.firstElement(named: "isbn")?.trimmedText
            }
        }
        return (metadata, coverID)
    }

    /// A person from an `<author>` or `<translator>`, by their names or,
    /// failing those, their nickname.
    private static func contributor(_ person: MarkupNode, role: String) -> Publication.Contributor? {
        let first = person.firstElement(named: "first-name")?.trimmedText
        let middle = person.firstElement(named: "middle-name")?.trimmedText
        let last = person.firstElement(named: "last-name")?.trimmedText
        let name = [first, middle, last].compactMap { $0 }.joined(separator: " ")
        guard !name.isEmpty else {
            return person.firstElement(named: "nickname")?.trimmedText.map {
                Publication.Contributor(name: $0, role: role)
            }
        }
        var sortAs: String?
        if let last {
            let given = [first, middle].compactMap { $0 }.joined(separator: " ")
            sortAs = given.isEmpty ? last : "\(last), \(given)"
        }
        return Publication.Contributor(name: name, sortAs: sortAs, role: role)
    }

    /// The annotation as plain text, a paragraph per line, since its
    /// markup is FictionBook rather than HTML.
    private static func plainSummary(_ annotation: MarkupNode) -> String? {
        let paragraphs = annotation.elements.compactMap(\.trimmedText)
        guard !paragraphs.isEmpty else { return annotation.trimmedText }
        return paragraphs.joined(separator: "\n")
    }

    private static func collapsed(_ text: String) -> String? {
        MarkupNode(name: "", children: [.text(text)]).trimmedText
    }
}
