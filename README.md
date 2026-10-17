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

> In development. EPUB publications open in `ReaderView` and turn page by page with taps, swipes, the keyboard or a trackpad. Other formats come after EPUB.

## Overview

Chek Reader is a standalone Swift package for reading on iPhone, iPad and Apple
Silicon Mac. It opens EPUB, PDF, comics, plain text, Markdown, MOBI, AZW3 and
FictionBook, from local files offline or streamed from a server.

It powers the [Chek](https://chek.page) app, but has no Chek-specific code, no
account and no server of its own, so any app can use it. Each format is its own
product, and apps compile only the formats they include.

## Requirements

- Xcode 27 and Swift 6.4 to build.
- Deploys to iOS 26, iPadOS 26 and macOS 26 or later. Features that need the 27 releases are behind availability checks.
- The core, format and navigator targets also build on Linux, which is how CI checks the parsers.

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/readchek/chek-reader.git", branch: "main"),
],
```

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
| `ChekReaderArchives` | Optional add-on for CBR and CB7. Not in the umbrella |

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
.provider(myProvider)                       // resources the app supplies, such as decrypted ones
.pages(myPageSource)                        // page images streamed one at a time
```

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

See [AGENTS.md](AGENTS.md) for the conventions contributors and coding agents follow.

## License

Apache License 2.0. See [LICENSE](LICENSE). Chek Reader isn't accepting outside contributions yet; see [CONTRIBUTING.md](CONTRIBUTING.md).
