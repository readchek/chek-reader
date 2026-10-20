#if os(iOS) && canImport(SwiftUI)
import CoreGraphics
import Foundation

/// Draws two pages into one picture, side by side, for showing a comic
/// as an open book. The pages meet in the middle with no gap, as printed
/// spreads do, and the shorter is scaled to the taller's height so the
/// top and bottom edges line up.
enum PageSpread {
    @concurrent
    static func compose(left: CGImage, right: CGImage) async -> CGImage? {
        let height = max(left.height, right.height)
        let leftWidth = Int(Double(left.width) * Double(height) / Double(max(left.height, 1)))
        let rightWidth = Int(Double(right.width) * Double(height) / Double(max(right.height, 1)))
        let width = leftWidth + rightWidth
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(left, in: CGRect(x: 0, y: 0, width: leftWidth, height: height))
        context.draw(right, in: CGRect(x: leftWidth, y: 0, width: rightWidth, height: height))
        return context.makeImage()
    }
}
#endif
