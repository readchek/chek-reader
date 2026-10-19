/// Reading settings the reader applies to reflowable text.
///
/// Changing them lays the text out again and keeps the same passage on
/// screen. Fixed-layout pages ignore them, since their layout is the
/// publisher's.
public struct ReaderPreferences: Hashable, Sendable {
    /// Colors for the page and its text.
    public enum Theme: String, Hashable, Sendable, CaseIterable {
        /// The publication's own colors.
        case original = "default"
        case light
        case sepia
        case dark
    }

    /// The typeface for body text.
    public enum Font: String, Hashable, Sendable, CaseIterable {
        /// The publication's own fonts.
        case original = "default"
        /// The system serif, New York on Apple platforms.
        case serif
        /// The system sans serif, San Francisco on Apple platforms.
        case sansSerif = "sans"
    }

    /// How a page turns.
    public enum PageTransition: String, Hashable, Sendable, CaseIterable {
        /// The page curls over like paper, following your finger.
        case curl
        /// The next page slides in beside this one, following your finger.
        case slide
    }

    /// How comic pages follow one another.
    public enum ComicFlow: String, Hashable, Sendable, CaseIterable {
        /// Vertical scrolling for webtoons, whose pages are tall strips,
        /// and turning pages for everything else.
        case automatic
        /// One page at a time, turned with ``PageTransition``.
        case paged
        /// Every page in one continuous column, scrolled vertically.
        case scrolled
    }

    /// The smallest and largest ``fontScale``.
    public static let fontScaleRange: ClosedRange<Double> = 0.5...3
    /// The smallest and largest ``lineHeight``.
    public static let lineHeightRange: ClosedRange<Double> = 1...2.5
    /// The smallest and largest ``marginScale``.
    public static let marginScaleRange: ClosedRange<Double> = 0...3

    /// Text size relative to the publication's, where 1 is unchanged.
    /// Values outside ``fontScaleRange`` are clamped.
    public var fontScale: Double {
        didSet { fontScale = Self.clamped(fontScale, to: Self.fontScaleRange, default: 1) }
    }
    public var theme: Theme
    public var font: Font
    /// Line height as a multiple of the text size, or `nil` for the
    /// publication's own. Values outside ``lineHeightRange`` are clamped.
    public var lineHeight: Double? {
        didSet { lineHeight = lineHeight.map { Self.clamped($0, to: Self.lineHeightRange, default: 1.5) } }
    }
    /// Page margins relative to the reader's standard ones, where 1 is
    /// unchanged and 0 runs text to the edges. Values outside
    /// ``marginScaleRange`` are clamped.
    public var marginScale: Double {
        didSet { marginScale = Self.clamped(marginScale, to: Self.marginScaleRange, default: 1) }
    }
    public var pageTransition: PageTransition
    public var comicFlow: ComicFlow

    public init(
        fontScale: Double = 1,
        theme: Theme = .original,
        font: Font = .original,
        lineHeight: Double? = nil,
        marginScale: Double = 1,
        pageTransition: PageTransition = .curl,
        comicFlow: ComicFlow = .automatic
    ) {
        self.fontScale = Self.clamped(fontScale, to: Self.fontScaleRange, default: 1)
        self.theme = theme
        self.font = font
        self.lineHeight = lineHeight.map { Self.clamped($0, to: Self.lineHeightRange, default: 1.5) }
        self.marginScale = Self.clamped(marginScale, to: Self.marginScaleRange, default: 1)
        self.pageTransition = pageTransition
        self.comicFlow = comicFlow
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>, default fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
