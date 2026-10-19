#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO

/// Decodes page images off the main thread, scaled down to the screen.
///
/// A comic page is often several times larger than the screen. Decoding
/// straight to the size it's shown at, rather than full size, keeps a page
/// turn within a frame or two and memory to a few screens' worth.
enum PageDecoder {
    /// The image in `data`, its longest side at most `maxPixelSize`, with
    /// its EXIF orientation applied. `nil` when ImageIO can't read it.
    ///
    /// With `minimumWidth`, tall pages decode larger so their width still
    /// fills the screen: a webtoon strip is shown at the screen's width and
    /// scrolled, not shrunk to fit its height.
    @concurrent
    static func decode(_ data: Data, maxPixelSize: Int, minimumWidth: Int = 0) async -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        var maxPixelSize = maxPixelSize
        if minimumWidth > 0,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > width {
            let forWidth = Int((Double(minimumWidth) * Double(height) / Double(width)).rounded(.up))
            maxPixelSize = min(max(maxPixelSize, forWidth), max(height, maxPixelSize), 16_384)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1),
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
#endif
