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
    @concurrent
    static func decode(_ data: Data, maxPixelSize: Int) async -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else { return nil }
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
