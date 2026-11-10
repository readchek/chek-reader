/// Tells a vertical strip, meant to be scrolled as a webtoon is, from pages
/// meant to be turned, by the sizes of a comic's first pages.
///
/// The web reader's `looksLikeStrip` is the same rule. Change both together.
enum StripDetection {
    /// A page's size in pixels.
    struct PageSize: Hashable, Sendable {
        var width: Int
        var height: Int
    }

    /// How many pages from the start are worth looking at.
    static let sampleCount = 5

    /// Whether pages of these sizes are a strip.
    ///
    /// A strip is either drawn as pages much taller than they are wide, or
    /// cut by its site into pieces of one width whose heights are whatever
    /// the cut left. Printed pages share a shape instead: a manga page is
    /// about 1.45 times as tall as wide and a comic about 1.55, and a
    /// spread among them is wider than its neighbors, not taller.
    static func looksLikeStrip(_ sizes: [PageSize]) -> Bool {
        let pages = sizes.filter { $0.width > 0 && $0.height > 0 }
        guard !pages.isEmpty else { return false }
        let ratios = pages.map { Double($0.height) / Double($0.width) }
        let tall = ratios.count { $0 > 2 }
        if tall * 2 > pages.count { return true }
        guard pages.count >= 3 else { return false }
        let widths = pages.map(\.width)
        guard let widest = widths.max(), let narrowest = widths.min(),
              Double(widest) <= Double(narrowest) * 1.02
        else { return false }
        // Cut pieces: taller than any printed page for the most part, or
        // of heights that differ far more than pages of one book do.
        let longish = ratios.count { $0 >= 1.7 }
        if longish * 2 > pages.count { return true }
        let heights = pages.map(\.height)
        guard let tallest = heights.max(), let shortest = heights.min(), let longest = ratios.max() else { return false }
        return Double(tallest) > Double(shortest) * 1.25 && longest >= 1.7
    }

    /// The page a scrolled strip counts as being read: the one under the
    /// reading line, or the last page once its foot is on screen. Short last
    /// pages never climb to the reading line, since the strip stops scrolling
    /// with them at the foot of the screen, so without this a strip read to
    /// its end would still report an earlier page. The web reader's `atEnd`
    /// is the same rule.
    static func pageBeingRead(probed: Int?, last: Int, lastFoot: Double?, screenFoot: Double) -> Int? {
        if last >= 0, let lastFoot, lastFoot <= screenFoot + 2 { return last }
        return probed
    }
}
