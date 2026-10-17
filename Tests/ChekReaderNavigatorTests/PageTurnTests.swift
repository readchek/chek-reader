import ChekReaderCore
@testable import ChekReaderNavigator
import Testing

@Suite struct PageTurnTests {
    @Test func turnsWithinAResourceThenIntoTheNext() {
        let middle = PagePosition(resource: 1, page: 2, pageCount: 5)
        #expect(PageTurn.forward(from: middle, resourceCount: 3) == .page(3))
        #expect(PageTurn.backward(from: middle) == .page(1))

        let lastPage = PagePosition(resource: 1, page: 4, pageCount: 5)
        #expect(PageTurn.forward(from: lastPage, resourceCount: 3) == .resource(2, atEnd: false))

        let firstPage = PagePosition(resource: 1, page: 0, pageCount: 5)
        #expect(PageTurn.backward(from: firstPage) == .resource(0, atEnd: true))
    }

    @Test func stopsAtTheEndsOfThePublication() {
        #expect(PageTurn.forward(from: PagePosition(resource: 2, page: 0, pageCount: 1), resourceCount: 3) == .none)
        #expect(PageTurn.backward(from: PagePosition(resource: 0, page: 0, pageCount: 4)) == .none)
    }

    @Test func reportsProgressionAtTheStartOfThePage() {
        #expect(PagePosition(resource: 0, page: 0, pageCount: 4).progression == 0)
        #expect(PagePosition(resource: 0, page: 3, pageCount: 4).progression == 0.75)
        #expect(PagePosition(resource: 0, page: 0, pageCount: 0).progression == 0)
    }

    @Test(arguments: [Publication.ReadingProgression.leftToRight, .auto])
    func mapsInputLeftToRight(_ progression: Publication.ReadingProgression) {
        #expect(PageCommand(.tap(.right), readingProgression: progression) == .forward)
        #expect(PageCommand(.tap(.left), readingProgression: progression) == .backward)
        #expect(PageCommand(.tap(.center), readingProgression: progression) == nil)
        #expect(PageCommand(.swipe(towardLeft: true), readingProgression: progression) == .forward)
        #expect(PageCommand(.key(.right), readingProgression: progression) == .forward)
        #expect(PageCommand(.key(.left), readingProgression: progression) == .backward)
    }

    @Test func mirrorsLeftAndRightForRightToLeftPublications() {
        let rtl = Publication.ReadingProgression.rightToLeft
        #expect(PageCommand(.tap(.left), readingProgression: rtl) == .forward)
        #expect(PageCommand(.tap(.right), readingProgression: rtl) == .backward)
        #expect(PageCommand(.swipe(towardLeft: false), readingProgression: rtl) == .forward)
        #expect(PageCommand(.key(.left), readingProgression: rtl) == .forward)
        // Keys that aren't sideways mean the same in either direction.
        #expect(PageCommand(.key(.next), readingProgression: rtl) == .forward)
        #expect(PageCommand(.key(.up), readingProgression: rtl) == .backward)
        #expect(PageCommand(.key(.end), readingProgression: rtl) == .lastPage)
        #expect(PageCommand(.wheel(forward: false), readingProgression: rtl) == .backward)
    }
}
