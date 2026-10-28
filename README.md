<p align="center">
  <img src=".github/assets/mark.svg" alt="Chek" width="80" height="80" />
</p>

<h1 align="center">Chek Reader</h1>

<p align="center">The reading engine behind Chek. Books, comics and documents for any Apple app.</p>

<p align="center">
  <a href="https://chek.page">Chek</a>
  ·
  <a href="AGENTS.md">Contributor guide</a>
  ·
  <a href="https://github.com/readchek/chek-reader/issues">Issues</a>
</p>

Chek Reader is a standalone Swift package for reading on iPhone, iPad and Apple
Silicon Mac. It powers [Chek 2.0](https://apps.apple.com/us/app/chek-books-comics/id6761271144)
on the App Store, but has no Chek-specific code, no account and no server of
its own, so any app can use it.

- Opens publications from local files offline, from memory, or streamed from
  an HTTP server.
- Turns pages with taps, swipes, the keyboard or a trackpad.
- Each format is its own product, so apps compile only the formats they include.

## Formats

| Format | How it reads |
| --- | --- |
| EPUB 2 and 3 | Reflowable and fixed layout, page by page |
| PDF | PDFKit's own view, a page at a time |
| CBZ, CBT | A page at a time, with `ComicInfo.xml` metadata and right-to-left manga |
| Plain text, Markdown | Converted to XHTML and read like EPUB, split into chapters at their headings |
| FictionBook | Plain or zipped, with embedded images and notes |
| MOBI, AZW3 | DRM-free books, rebuilt into HTML documents |
| CBR, CB7 | Through the optional archives add-on, which links libarchive |

## Requirements

- Xcode 27 and Swift 6.4 to build.
- Deploys to iOS 26, iPadOS 26 and macOS 26 or later. Features that need the 27 releases are behind availability checks.
- The core, format and navigator targets also build on Linux, which is how CI checks the parsers.

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/readchek/chek-reader.git", from: "0.1.0"),
],
```

Releases are tags on `main` named by version, such as `0.1.0`; `from:` takes
that release and later ones up to the next major. To follow unreleased
changes instead, depend on `branch: "main"`. Maintainers cut a release by
running the Release workflow in the Actions tab with the version, which tags
`main` and pushes the tag.

Then pick the products the app needs. Apps only compile and ship the formats they include.

| Product | What it adds |
| --- | --- |
| `ChekReader` | Everything in the default set: all formats below except CBR and CB7, plus the navigator and UI |
| `ChekReaderCore` | Publication model, positions, limits, errors and format detection. Required by everything else |
| `ChekReaderEPUB` | EPUB 2 and 3, reflowable and fixed layout |
| `ChekReaderPDF` | PDF through PDFKit |
| `ChekReaderComics` | CBZ, CBT and webtoons |
| `ChekReaderText` | Plain text and Markdown |
| `ChekReaderMOBI` | DRM-free MOBI and AZW3 |
| `ChekReaderFB2` | FictionBook, plain and zipped |
| `ChekReaderNavigator` | `ReaderController` and the content views, for apps that draw their own controls |
| `ChekReaderUI` | `ReaderView` with the standard Liquid Glass controls |
| `ChekReaderArchives` | Optional add-on for CBR and CB7, linking libarchive. Not in the umbrella |

## Usage

Register the formats once at launch, then show a reader:

```swift
import ChekReader
import SwiftUI

@main
struct MyApp: App {
    init() {
        ReaderFormats.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ReaderView(source: .file(bookURL))
        }
    }
}
```

`ReaderView` draws the standard controls: a tap in the middle of the page shows a title bar with the table of contents, search and appearance settings, and a slider through the book's positions. Pass the location and settings saved last time, and keep what the reader reports back:

```swift
ReaderView(
    source: .file(bookURL),
    initialLocation: savedLocation,
    preferences: savedPreferences,
    onLocationChange: { save($0) },
    onPreferencesChange: { savePreferences($0) }
)
```

Apps that draw their own interface around `NavigatorView` can reuse the pieces on their own: `ReaderControls`, `TableOfContentsView`, `SearchView` and `AppearanceView` each take a `ReaderController`.

An app that links only some format products registers those instead:

```swift
import ChekReaderEPUB
import ChekReaderPDF

ReaderFormats.register(EPUBModule.self, PDFModule.self)
```

Opening a format the app didn't include fails with `ReaderError.formatNotIncluded`, whose recovery suggestion names the product to add.

Publications can come from several sources:

```swift
.file(url)                                  // a file on disk
.data(data, fileName: "book.epub")          // bytes in memory
.remote(url, RemoteOptions { request in     // an HTTP server; EPUB and CBZ load by range
    var request = request
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return request
})
.remote(url, RemoteOptions(load: myLoader)) // or send requests through your own session
.provider(myProvider)                       // resources the app supplies, such as decrypted ones
.pages(myPageSource)                        // page images streamed one at a time
```

Formats that keep everything in one file, such as PDF and MOBI, download the whole file from a URL, and ask a provider for it with the empty href `PublicationSource.wholePublicationHref`.

To read a publication's structure without showing it, for example to import a library, open it directly:

```swift
let publication = try await Publication.open(.file(bookURL))
publication.metadata.title             // the title, when the book has one
publication.readingOrder               // chapters, in order
publication.tableOfContents            // nested entries with titles and hrefs
let html = try await publication.data(at: publication.readingOrder[0].href)
```

Damaged but readable files still open, and what was repaired or skipped is listed in `publication.warnings`. Every archive and XML document is checked against `ReaderLimits` while it's read, and DRM-protected books fail with `ReaderError.drmProtected`.

Reading positions are `Locator` values. Their JSON matches the Readium Locator model, so they can be stored and synced as-is.

To control the reader yourself, keep a `ReaderController` and show it with `NavigatorView`. Locations carry the text at the start of the page, so a saved location lands on the same passage after the text size or screen changes, and a position number and total progression once the book's positions are worked out:

```swift
let controller = ReaderController(preferences: ReaderPreferences(fontScale: 1.2, theme: .sepia))
try await controller.open(.file(bookURL), at: savedLocation)

controller.location?.locations.position          // like a page number that doesn't change with the text size
controller.location?.locations.totalProgression  // 0 to 1 through the whole book
await controller.goForward()
await controller.setPreferences(ReaderPreferences(fontScale: 1.5, theme: .dark))
```

To go on to a series' next chapter when the reader turns past the last page, watch `turnsPastEnd`. It counts taps, keys and swipes toward a next page that isn't there, and pulls past the end of a scrolled comic. PDF doesn't report them yet:

```swift
.onChange(of: controller.turnsPastEnd) {
    openNextChapter()
}
```

Searching reads every chapter, so run it off the critical path. Each result is a `Locator` with the matched text and the words around it, in reading order, that `go(to:)` opens at the page holding the match. PDF searches through PDFKit, and comics find nothing:

```swift
let results = try await controller.search(for: "lighthouse", options: SearchOptions(caseSensitive: false, limit: 100))
results.first?.text        // before, highlight and after
results.first?.title       // the chapter's title, when the table of contents names it
await controller.go(to: results[0])
```

## Repository layout

```text
Package.swift
Sources/
  ChekReaderCore/        Publication model, Locator, formats, limits, errors
  ChekReaderEPUB/ …      One target per format product
  ChekReaderNavigator/   ReaderController and content views
  ChekReaderUI/          ReaderView and standard controls
  ChekReader/            Umbrella product
Tests/                   Swift Testing suites per target
Examples/ChekReaderDemo/ Read-only document viewer for iPhone, iPad and Mac
Scripts/Reader/          TypeScript page layout script, compiled into ChekReaderNavigator
Web/                     Chek Reader for the web, the @readchek/reader package
Benchmarks/              Comparison with Readium, PDFKit and other readers (see Benchmarks/README.md)
.github/workflows/       CI
```

## Development

You can work without a phone: the demo app runs natively on an Apple Silicon Mac and in the iOS Simulator.

```sh
swift test                                                  # core, formats and navigator, on macOS or Linux
xcodebuild test -scheme ChekReader-Package -destination 'platform=macOS'
open Examples/ChekReaderDemo/ChekReaderDemo.xcodeproj       # demo app
```

The page layout script is TypeScript in `Scripts/Reader`, compiled into `Sources/ChekReaderNavigator/Resources/reader.js`, which is committed so the package builds without Node. After changing the script, rebuild it and run its browser tests:

```sh
cd Scripts/Reader
npm ci
npx playwright install webkit
npm test                                                    # compiles, then tests in WebKit
```

## Chek Reader for the web

`@readchek/reader` is the reader for web apps, in `Web/`. It reads comics, EPUB books, plain text, Markdown and PDF. `ComicView` shows a comic's pages in an element you give it, one page or a spread at a time, left to right or right to left, or as one scrolling column for webtoons. It saves positions as the same `Locator` JSON as the Swift package, so a place saved in a browser opens on iPhone. Apps draw their own controls and fetch the pages.

```ts
import { ComicView } from "@readchek/reader"

const view = new ComicView(element, { count, load: (index, signal) => fetchPage(index, signal) }, {
	location: (place) => save(place.locator),
	tap: () => toggleControls(),
})
```

Books open with `Epub` and `BookView`. `Epub.open(file)` reads an EPUB from a `Blob`, with its contents, reading order and metadata, and throws `DrmError` for encrypted books. `BookView` pages it in an element you give it, using the same `reader.js` layout script as the Swift package, so pages, themes and locators match the iPhone app.

```ts
import { BookView, Epub } from "@readchek/reader"

const epub = await Epub.open(await response.blob())
const view = new BookView(element, epub, {
	location: (place) => save(place.locator),
	tap: () => toggleControls(),
	end: () => showUpNext(),
	externalLink: (url) => open(url, "_blank", "noopener"),
	error: (error) => show(error),
}, { frameUrl: "/reader-frame/frame.html" }, savedLocator)
```

Each page is in a sandboxed frame, so while it has focus the app's document doesn't see key presses or mouse moves. `BookView` passes the keys it doesn't use, such as Escape, to the `key` event, and reports mouse moves over the page to the `pointer` event, for apps that show their controls on hover. `chapterAt(progression)` names the chapter at a point through the book, such as under a slider's thumb.

Plain text and Markdown open with `TextBook.plainText(file, fileName)` and `TextBook.markdown(file, fileName)`, which convert them to XHTML chapters exactly as the Swift package does, and read in `BookView` like any EPUB.

PDFs open from a separate entry, `@readchek/reader/pdf`, which uses [pdf.js](https://github.com/mozilla/pdf.js) (Apache-2.0). Install `pdfjs-dist` at the version in this package's `peerDependencies` to use it. Apps that never import it don't need pdf.js. `PdfDocument` draws each page with pdf.js and reads in `ComicView`, with the Swift package's PDF locators. Serve pdf.js's worker from your app's origin, and its `cmaps` and `standard_fonts` folders for PDFs that don't embed their fonts:

```ts
const { PdfDocument } = await import("@readchek/reader/pdf")
const pdf = await PdfDocument.open(file, { worker: "/pdfjs/pdf.worker.min.mjs", cMaps: "/pdfjs/cmaps/", standardFonts: "/pdfjs/standard_fonts/" })
const view = new ComicView(element, pdf, events, { flow: "paged" }, savedLocator)
```

Each part of a book opens in an iframe sandboxed with `allow-scripts` only, so it has no access to your app's origin, storage or cookies. Scripts in the book are removed before it opens. The frame's files are in `Web/dist/frame`. Serve them from your app's origin at the `frameUrl` you pass, and give that path its own content security policy, since book styles are inline:

```
default-src 'none'; script-src 'self'; style-src 'unsafe-inline' blob:; img-src blob: data:; font-src blob: data:; media-src blob:; base-uri 'none'; form-action 'none'; frame-ancestors 'self'
```

Position the element you pass to `ComicView` or `BookView` and give it a size. The views fill it.

It isn't on npm yet. Install it from this repository at a commit or tag, such as `bun add github:readchek/chek-reader#<tag>`. The compiled `Web/dist` is committed for that reason, and CI fails if it differs from `Web/src`. After changing the source:

```sh
npm ci
npm test                                                    # compiles Web/src into Web/dist, then tests it
```

See [AGENTS.md](AGENTS.md) for the conventions contributors and coding agents follow.

## Dependencies

The core, format and UI products depend only on Apple frameworks and the Swift standard library.

The optional `ChekReaderArchives` product links [libarchive](https://github.com/libarchive/libarchive) (BSD-2-Clause):

- **On Apple platforms**, as a prebuilt static XCFramework from [Lakr233/libarchive.xcframework](https://github.com/Lakr233/libarchive.xcframework), pinned to one release. Its packaging is MIT, with xz, zstd and lz4 under 0BSD and BSD licenses.
- **On Linux**, as the system library from `libarchive-dev`.

The web package's optional `@readchek/reader/pdf` entry uses [pdf.js](https://github.com/mozilla/pdf.js) (`pdfjs-dist`, Apache-2.0), an optional peer dependency pinned to one release. The rest of the web package has no dependencies.

Register it alongside the defaults to read CBR and CB7:

```swift
import ChekReaderArchives

ReaderFormats.registerDefaults()
ReaderFormats.register(ArchivesModule.self)
```

## License

Apache License 2.0. See [LICENSE](LICENSE). Chek Reader isn't accepting outside contributions yet; see [CONTRIBUTING.md](CONTRIBUTING.md).
