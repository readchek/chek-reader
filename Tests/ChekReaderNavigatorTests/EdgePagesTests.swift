@testable import ChekReaderNavigator
import Testing

/// How turns move through the pages outside a publication's: its end's
/// own page, then the page past it, and back.
@Suite struct EdgePagesTests {
    @Test func turningOnFromTheEndsPageGoesPastIt() {
        #expect(OutsidePlace.edge(.end).turned(forward: true) == .past(.end))
        #expect(OutsidePlace.past(.end).turned(forward: true) == nil)
        #expect(!OutsidePlace.past(.end).isInside(afterTurning: true))
    }

    @Test func turningBackFromTheEndsPageReturnsToTheLastPage() {
        #expect(OutsidePlace.edge(.end).isInside(afterTurning: false))
        #expect(OutsidePlace.edge(.end).turned(forward: false) == nil)
        #expect(OutsidePlace.past(.end).turned(forward: false) == .edge(.end))
    }

    @Test func theStartMirrorsTheEnd() {
        #expect(OutsidePlace.edge(.start).turned(forward: false) == .past(.start))
        #expect(OutsidePlace.edge(.start).isInside(afterTurning: true))
        #expect(OutsidePlace.past(.start).turned(forward: true) == .edge(.start))
        #expect(OutsidePlace.past(.start).turned(forward: false) == nil)
    }

    @Test func eachPlaceKnowsItsEnd() {
        #expect(OutsidePlace.past(.start).edge == .start)
        #expect(OutsidePlace.edge(.end).edge == .end)
    }
}
