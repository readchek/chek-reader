import ChekReaderCore
@testable import ChekReaderNavigator
import Testing

@Suite struct PDFPageLocationTests {
    private func locator(fragments: [String] = [], progression: Double? = nil) -> Locator {
        Locator(href: "publication.pdf", mediaType: "application/pdf", locations: .init(fragments: fragments, progression: progression))
    }

    @Test func pageFragmentWins() {
        #expect(PDFPageLocation.pageIndex(of: locator(fragments: ["page=3"], progression: 0.9), pageCount: 10) == 2)
        #expect(PDFPageLocation.pageIndex(of: locator(fragments: ["zoom=2&page=4"]), pageCount: 10) == 3)
        #expect(PDFPageLocation.pageIndex(of: locator(fragments: ["page=40"]), pageCount: 10) == 9)
    }

    @Test func progressionPicksThePage() {
        #expect(PDFPageLocation.pageIndex(of: locator(progression: 0.4), pageCount: 5) == 2)
        #expect(PDFPageLocation.pageIndex(of: locator(), pageCount: 5) == 0)
        #expect(PDFPageLocation.pageIndex(of: locator(progression: .nan), pageCount: 5) == 0)
        #expect(PDFPageLocation.pageIndex(of: locator(progression: 1), pageCount: 5) == 4)
        #expect(PDFPageLocation.pageIndex(of: locator(), pageCount: 0) == nil)
    }

    @Test func titlesAreInPageOrder() {
        let toc = [
            Link(href: "publication.pdf#page=5", title: "Two", children: [Link(href: "publication.pdf#page=6", title: "Two A")]),
            Link(href: "publication.pdf#page=1", title: "One"),
            Link(href: "publication.pdf", title: "No page"),
        ]
        let titles = PDFPageLocation.titles(in: toc)
        #expect(titles.map(\.page) == [0, 4, 5])
        #expect(titles.map(\.title) == ["One", "Two", "Two A"])
    }
}
