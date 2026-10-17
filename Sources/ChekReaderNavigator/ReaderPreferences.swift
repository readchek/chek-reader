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

    /// The smallest and largest ``fontScale``.
    public static let fontScaleRange: ClosedRange<Double> = 0.5...3

    /// Text size relative to the publication's, where 1 is unchanged.
    /// Values outside ``fontScaleRange`` are clamped.
    public var fontScale: Double {
        didSet { fontScale = Self.clamped(fontScale) }
    }
    public var theme: Theme

    public init(fontScale: Double = 1, theme: Theme = .original) {
        self.fontScale = Self.clamped(fontScale)
        self.theme = theme
    }

    private static func clamped(_ scale: Double) -> Double {
        scale.isFinite ? min(max(scale, fontScaleRange.lowerBound), fontScaleRange.upperBound) : 1
    }
}
