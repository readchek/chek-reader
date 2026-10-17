import ChekReaderCore
import Testing

@Suite struct PositionListTests {
    private let chapters = ["a.xhtml", "b.xhtml", "c.xhtml"].map {
        Locator(href: $0, mediaType: "application/xhtml+xml", locations: Locator.Locations(fragments: ["x"], progression: 0.5))
    }

    @Test func numbersPositionsAcrossResources() {
        let list = PositionList(readingOrder: chapters, counts: [3, 1, 0])
        #expect(list.count == 5)
        #expect(list.locators.map(\.href) == ["a.xhtml", "a.xhtml", "a.xhtml", "b.xhtml", "c.xhtml"])
        #expect(list.locators.map(\.locations.position) == [1, 2, 3, 4, 5])
        #expect(list.locators.map(\.locations.totalProgression) == [0, 0.2, 0.4, 0.6, 0.8])
        #expect(list.locators[1].locations.progression == 1.0 / 3)
        // Fragments belong to a link, not to a position.
        #expect(list.locators.allSatisfy { $0.locations.fragments.isEmpty })
    }

    @Test func findsLocatorsByPositionAndProgression() {
        let list = PositionList(readingOrder: chapters, counts: [3, 1, 1])
        #expect(list.locator(at: 4)?.href == "b.xhtml")
        #expect(list.locator(at: 0) == nil)
        #expect(list.locator(at: 6) == nil)
        #expect(list.locator(atTotalProgression: 0)?.locations.position == 1)
        #expect(list.locator(atTotalProgression: 0.5)?.locations.position == 3)
        #expect(list.locator(atTotalProgression: 1)?.locations.position == 5)
        #expect(list.locator(atTotalProgression: .nan) == nil)
    }

    @Test func locatesAPositionFromProgressionInAResource() {
        let list = PositionList(readingOrder: chapters, counts: [4, 1, 1])
        var locator = Locator(href: "a.xhtml", mediaType: "application/xhtml+xml")
        locator.locations.progression = 0.6
        let located = list.locate(locator, inResource: 0)
        #expect(located.locations.position == 3)
        #expect(located.locations.totalProgression == 0.4)

        locator.locations.progression = 1
        #expect(list.locate(locator, inResource: 0).locations.position == 4)
        #expect(list.locate(locator, inResource: 9) == locator)
    }
}
