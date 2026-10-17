# Chek Reader

A reading engine for Apple platforms, with optional UI. It opens EPUB, PDF, comics, plain text, Markdown, MOBI, AZW3 and FictionBook on iPhone, iPad and Apple Silicon Macs. It reads local files offline and streams publications from URLs, and it has no account, server or app-specific code of its own.

> **Status: early development.** The package structure, format detection, positions and the session controller are in place. The format engines are not, so opening a publication currently reports that its format is not implemented yet.

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

Reading positions are `Locator` values. Their JSON matches the Readium Locator model, so they can be stored and synced as-is.

## Repository layout

```
Package.swift
Sources/
  ChekReaderCore/        Publication model, Locator, formats, limits, errors
  ChekReaderEPUB/ …      One target per format product
  ChekReaderNavigator/   ReaderController and content views
  ChekReaderUI/          ReaderView and standard controls
  ChekReader/            Umbrella product
Tests/                   Swift Testing suites per target
Examples/ChekReaderDemo/ Read-only document viewer for iPhone, iPad and Mac
.github/workflows/       CI
```

## Development

You can work without a phone: the demo app runs natively on an Apple Silicon Mac and in the iOS Simulator.

```sh
swift test                                                  # core, formats and navigator, on macOS or Linux
xcodebuild test -scheme ChekReader-Package -destination 'platform=macOS'
open Examples/ChekReaderDemo/ChekReaderDemo.xcodeproj       # demo app
```

See [AGENTS.md](AGENTS.md) for the conventions contributors and coding agents follow.

## License

Apache License 2.0. See [LICENSE](LICENSE).
