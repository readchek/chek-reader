import ChekReaderCore
import Foundation

/// The metadata in a comic's `ComicInfo.xml`, the ComicRack schema most
/// comic tools write.
struct ComicInfo: Sendable {
    var metadata = Publication.Metadata(layout: .fixed)
    /// The 0-based page of the front cover, when it's marked.
    var coverPage: Int?
    /// Bookmarked pages, 0-based, with their titles.
    var bookmarks: [(page: Int, title: String)] = []

    init() {}

    init(_ root: MarkupNode) {
        func text(_ name: String) -> String? {
            root.firstElement(named: name)?.trimmedText
        }
        func list(_ name: String) -> [String] {
            (text(name) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        metadata.title = text("Title")
        if let series = text("Series") {
            metadata.series = Publication.Series(name: series, position: text("Number").flatMap(Double.init))
            if metadata.title == nil {
                metadata.title = [series, text("Number").map { "#\($0)" }].compactMap { $0 }.joined(separator: " ")
            }
        }
        metadata.summary = text("Summary")
        metadata.authors = list("Writer").map { Publication.Contributor(name: $0, role: "aut") }
        let roles = [
            ("Penciller", "ill"), ("Inker", "ink"), ("Colorist", "clr"), ("Letterer", "ltr"),
            ("CoverArtist", "cov"), ("Editor", "edt"), ("Translator", "trl"),
        ]
        metadata.contributors = roles.flatMap { element, role in
            list(element).map { Publication.Contributor(name: $0, role: role) }
        }
        metadata.publishers = list("Publisher")
        metadata.subjects = list("Genre")
        metadata.languages = text("LanguageISO").map { [$0] } ?? []
        if let year = text("Year").flatMap(Int.init), year > 0 {
            var date = String(format: "%04d", year)
            if let month = text("Month").flatMap(Int.init), (1...12).contains(month) {
                date += String(format: "-%02d", month)
                if let day = text("Day").flatMap(Int.init), (1...31).contains(day) {
                    date += String(format: "-%02d", day)
                }
            }
            metadata.published = date
        }
        if text("Manga") == "YesAndRightToLeft" {
            metadata.readingProgression = .rightToLeft
        }
        metadata.identifier = text("GTIN")

        for page in root.firstElement(named: "Pages")?.elements(named: "Page") ?? [] {
            guard let index = page.attribute("Image").flatMap(Int.init), index >= 0 else { continue }
            if page.attribute("Type") == "FrontCover", coverPage == nil {
                coverPage = index
            }
            if let bookmark = page.attribute("Bookmark")?.trimmingCharacters(in: .whitespaces), !bookmark.isEmpty {
                bookmarks.append((index, bookmark))
            }
        }
    }
}
