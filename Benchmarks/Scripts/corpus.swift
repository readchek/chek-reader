// Fetches and generates the benchmark corpus described in Benchmarks/corpus.json.
//
//   swift Benchmarks/Scripts/corpus.swift [output directory]
//
// The output directory defaults to Benchmarks/ReaderBench/Corpus, which the
// benchmark app bundles. Alongside the files it writes manifest.json, which
// the app reads to find each fixture. Requires macOS, because the synthetic
// fixtures are drawn with Core Graphics and Core Text.

import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Corpus: Decodable {
    struct Fixture: Decodable {
        struct Generator: Decodable {
            var type: String
            var pages: Int
            var width: Int?
            var height: Int?
        }

        var id: String
        var kind: String
        var role: String
        var source: String?
        var license: String
        var sha256: String?
        var generator: Generator?
    }

    var fixtures: [Fixture]
}

struct ManifestEntry: Encodable {
    var id: String
    var kind: String
    var role: String
    var file: String
    var bytes: Int
    var sha256: String
    var source: String
    var license: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func sha256(of url: URL) throws -> String {
    let digest = SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// A small deterministic generator, so synthetic fixtures are identical on every machine.
struct SeededGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}

let words = """
    reader page chapter margin column spread glyph line paragraph quiet window river evening letter \
    morning garden distance silver harbor lantern question answer journey winter summer promise \
    history mountain village candle shadow silence thunder meadow figure surface pattern balance
    """.split(separator: " ").map(String.init)

func paragraph(_ rng: inout SeededGenerator, words count: Int) -> String {
    var result: [String] = []
    for index in 0..<count {
        var word = words[Int(rng.next() % UInt64(words.count))]
        if index == 0 { word = word.capitalized }
        result.append(word)
    }
    return result.joined(separator: " ") + "."
}

func generatePDF(pages: Int, to url: URL) {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        fail("could not create \(url.path)")
    }
    var rng = SeededGenerator(state: 1_000)
    let font = CTFontCreateWithName("Times New Roman" as CFString, 11, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
    ]
    for page in 1...pages {
        context.beginPDFPage(nil)
        var text = "Page \(page)\n\n"
        for _ in 0..<6 {
            text += paragraph(&rng, words: 70) + "\n\n"
        }
        let string = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: mediaBox.insetBy(dx: 72, dy: 72), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
        context.endPDFPage()
    }
    context.closePDF()
}

func generateComic(pages: Int, width: Int, height: Int, to url: URL) {
    let fileManager = FileManager.default
    let scratch = fileManager.temporaryDirectory.appendingPathComponent("chek-comic-\(UUID().uuidString)")
    try! fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: scratch) }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    // Noise defeats JPEG compression the way detailed line art and screentone
    // do, so pages land at a realistic size of one to three megabytes each.
    func noiseTile(seed: UInt64) -> CGImage {
        let side = 256
        var rng = SeededGenerator(state: seed)
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8(truncatingIfNeeded: rng.next())
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    for page in 1...pages {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        )!
        let tile = noiseTile(seed: UInt64(page))
        context.draw(tile, in: CGRect(x: 0, y: 0, width: 256, height: 256), byTiling: true)

        // Panels with flat fills and borders, like a real page layout.
        var rng = SeededGenerator(state: UInt64(page) &* 31)
        let rows = 3
        let panelHeight = CGFloat(height - 120) / CGFloat(rows)
        for row in 0..<rows {
            let rect = CGRect(x: 60, y: 60 + CGFloat(row) * panelHeight, width: CGFloat(width - 120), height: panelHeight - 40)
            let gray = CGFloat(rng.next() % 200) / 255
            context.setFillColor(CGColor(gray: gray, alpha: 0.55))
            context.fill(rect)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineWidth(8)
            context.stroke(rect)
        }

        let image = context.makeImage()!
        let fileURL = scratch.appendingPathComponent(String(format: "%03d.jpg", page))
        let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { fail("could not write \(fileURL.path)") }
    }

    // Stored entries, as most real CBZ files use, with no extra attributes so
    // the archive is byte-for-byte reproducible.
    try? fileManager.removeItem(at: url)
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = scratch
    zip.arguments = ["-0", "-X", "-q", "-r", url.path, "."]
    try! zip.run()
    zip.waitUntilExit()
    guard zip.terminationStatus == 0 else { fail("zip failed for \(url.path)") }
}

let scriptDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let benchmarks = scriptDirectory.deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : benchmarks.appendingPathComponent("ReaderBench/Corpus")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: benchmarks.appendingPathComponent("corpus.json")))
var manifest: [ManifestEntry] = []

for fixture in corpus.fixtures {
    let file = "\(fixture.id).\(fixture.kind)"
    let url = output.appendingPathComponent(file)
    let exists = FileManager.default.fileExists(atPath: url.path)

    if let source = fixture.source {
        if !exists || (fixture.sha256 != nil && (try? sha256(of: url)) != fixture.sha256) {
            print("Downloading \(fixture.id) from \(source)")
            guard let remote = URL(string: source) else { fail("bad URL for \(fixture.id)") }
            do {
                try Data(contentsOf: remote).write(to: url, options: .atomic)
            } catch {
                fail("could not download \(fixture.id): \(error.localizedDescription)")
            }
        }
    } else if let generator = fixture.generator, !exists {
        print("Generating \(fixture.id)")
        switch generator.type {
        case "pdf":
            generatePDF(pages: generator.pages, to: url)
        case "comic":
            generateComic(pages: generator.pages, width: generator.width ?? 1800, height: generator.height ?? 2700, to: url)
        default:
            fail("unknown generator \(generator.type) for \(fixture.id)")
        }
    }

    let checksum = try sha256(of: url)
    if let expected = fixture.sha256, expected != checksum {
        fail("\(fixture.id) has checksum \(checksum), but corpus.json pins \(expected). Check the source, then update the pin.")
    }
    let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("\(fixture.id): \(bytes) bytes, sha256 \(checksum)\(fixture.sha256 == nil ? " (not pinned)" : "")")
    manifest.append(ManifestEntry(
        id: fixture.id, kind: fixture.kind, role: fixture.role, file: file, bytes: bytes,
        sha256: checksum, source: fixture.source ?? "generated", license: fixture.license
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(manifest).write(to: output.appendingPathComponent("manifest.json"))
print("Wrote \(manifest.count) fixtures to \(output.path)")
