@testable import ChekReaderNavigator
import Testing

/// The same cases as the web reader's `flow.test.mjs`, so the two agree.
@Suite struct StripDetectionTests {
    private func page(_ width: Int, _ height: Int) -> StripDetection.PageSize {
        StripDetection.PageSize(width: width, height: height)
    }

    @Test func pagesMuchTallerThanWideAreAStrip() {
        #expect(StripDetection.looksLikeStrip([page(800, 12000), page(800, 9000), page(800, 1100)]))
    }

    @Test func aStripCutIntoShortPiecesOfOneWidthIsStillAStrip() {
        // Under twice as tall as wide, which the old rule took for pages.
        #expect(StripDetection.looksLikeStrip([page(720, 1280), page(720, 1280), page(720, 1280), page(720, 1280)]))
        #expect(StripDetection.looksLikeStrip([page(800, 1000), page(800, 1400), page(800, 900), page(800, 1390)]))
    }

    @Test func mangaAndComicPagesArePages() {
        #expect(!StripDetection.looksLikeStrip([page(1115, 1600), page(1115, 1600), page(1115, 1600), page(1115, 1600)]))
        #expect(!StripDetection.looksLikeStrip([page(1988, 3056), page(1988, 3056), page(1988, 3056)]))
    }

    @Test func aSpreadAmongPagesDoesNotMakeThemAStrip() {
        #expect(!StripDetection.looksLikeStrip([page(1115, 1600), page(2230, 1600), page(1115, 1600), page(1115, 1600)]))
    }

    @Test func pagesOfSlightlyDifferentScansStayPages() {
        #expect(!StripDetection.looksLikeStrip([page(1100, 1600), page(1120, 1590), page(1108, 1610), page(1115, 1600)]))
    }

    @Test func nothingToLookAtIsNotAStrip() {
        #expect(!StripDetection.looksLikeStrip([]))
        #expect(!StripDetection.looksLikeStrip([page(0, 0)]))
    }
}
