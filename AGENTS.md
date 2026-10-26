# AGENTS.md

Guidance for anyone changing this repository, human or agent. Read it before writing code.

## What this is

Chek Reader is a standalone Swift package for reading publications on iPhone, iPad and Apple Silicon Mac. It's built for any app to use. The Chek app is one client, but nothing in this repository may depend on Chek or know about it. The goal for 1.0 is to be on par with or better than every existing reader package, including Readium's Swift toolkit, Apple Books, Preview for PDF and ChibiManga's current renderer, with published benchmarks to show it.

## Decisions already made

Treat these as settled. Raise a change with the maintainer instead of working around one.

- **Own engine.** Don't adopt or wrap Readium or another reader. The `Locator` JSON stays Readium-compatible for interoperability.
- **SwiftPM only.** No CocoaPods or Carthage. Each format is its own product, so apps compile only the formats they include. The `ChekReader` umbrella re-exports the default set.
- **Platforms.** Build with Xcode 27 and Swift 6.4, and deploy to iOS, iPadOS and macOS 26 or later. Put 27-only APIs behind `@available(anyAppleOS 27, *)` or `if #available`. Mac Catalyst isn't supported, because the SwiftUI `WebPage` APIs are unavailable there.
- **Web.** The web reader is a TypeScript package in `Web`, with no framework and no dependencies, under the same license. It draws pages into an element and leaves controls, storage and networking to the app. Its locators match the Swift package's.
- **Rendering.** Reflowable formats render through SwiftUI `WebView` and `WebPage`, with a TypeScript pagination layer. PDF uses PDFKit, and comics use ImageIO with Core Animation.
- **Formats in 1.0.** EPUB 2 and 3, PDF, CBZ, CBT, TXT, Markdown, DRM-free MOBI and AZW3, and FB2. CBR and CB7 live in the optional `ChekReaderArchives` add-on, which links libarchive.
- **No DRM.** Don't decrypt DRM. Report `ReaderError.drmProtected`, and let apps decrypt through a `ResourceProvider`.
- **Remote sources.** Opening from URLs is in scope. ZIP-based formats read entries with HTTP Range requests, and page servers stream images through `PageSource`. The app supplies credentials through `RemoteOptions`. OPDS catalogs stay with each app for now.
- **Publication scripts.** They're off by default, and apps can opt in. Publication content never makes network requests.
- **Order of work.** Reflowable EPUB first, then every other format, then controls, accessibility and search, then hardening.
- **License.** Apache-2.0.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/ChekReaderCore` | Formats, `FormatSniffer`, `Publication` model, `Locator`, `PublicationSource`, `ReaderLimits`, `ReaderError`, `ReaderFormats` registry, and the ZIP and XML readers formats share through `package` access. No UI frameworks |
| `Sources/ChekReader<Format>` | One target per format product. Each one exposes a `ReaderFormatModule` |
| `Sources/ChekReaderNavigator` | `ReaderController` session state machine and content views |
| `Sources/ChekReaderUI` | `ReaderView` and the standard controls |
| `Sources/ChekReader` | Umbrella: re-exports and `ReaderFormats.registerDefaults()` |
| `Tests/` | Swift Testing suites, one target per source target |
| `Examples/ChekReaderDemo` | Read-only document viewer built on the SwiftUI `Document` protocol |
| `Scripts/Reader` | TypeScript page layout script. It compiles into `Sources/ChekReaderNavigator/Resources/reader.js`, which is committed; CI fails if the two differ |
| `Web` | Chek Reader for the web, the `@readchek/reader` TypeScript package, starting with comics. Its `package.json` is at the root so apps can install it from GitHub. `Web/dist` is committed; CI fails if it differs from `Web/src` |
| `Benchmarks` | Benchmark app and corpus comparing readers in the simulator; links Readium only to measure it. See its README |

## Build and test

```sh
swift build
swift test
xcodebuild test -scheme ChekReader-Package -destination 'platform=macOS'
xcodebuild build -scheme ChekReader-Package -destination 'generic/platform=iOS Simulator'
xcodebuild build -project Examples/ChekReaderDemo/ChekReaderDemo.xcodeproj -scheme ChekReaderDemo \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO
```

After changing `Scripts/Reader`, run `npm ci && npm test` there and commit the rebuilt `reader.js`. After changing `Web`, run `npm ci && npm test` at the root and commit the rebuilt `Web/dist`.

CI runs all of these, and also builds and tests the package on Linux. It can run on the maintainers' own Mac and Linux machines, switched by repository variables; see `.github/RUNNERS.md` before changing where a job runs. Keep the core, format and navigator targets free of UIKit, AppKit and SwiftUI so the Linux job keeps passing. Wrap SwiftUI code in `#if canImport(SwiftUI)`.

Before you push, build and test whatever you changed. If your environment can't build a target, say so in the PR rather than guessing.

## Code conventions

- **Swift 6 language mode, strict concurrency and strict memory safety** are on for every target. Don't turn them off or silence them per file.
- **Dependencies.** Core and format products depend only on Apple frameworks and the Swift standard library. An optional product may take a dependency when its format needs one. Pin it, check its license and list it in the README.
- **Public API.** Everything public is `Sendable`, documented with a DocC comment, and honors task cancellation. Ordinary navigation misses, such as going past the last page, return a result instead of throwing.
- **Errors.** Failures are `ReaderError` cases, thrown with typed `throws(ReaderError)` where practical. Messages are written for the developer integrating the package and say what to do next.
- **Limits.** Every parser enforces `ReaderLimits`, and exceeding one fails with `.limitExceeded`. Never trust sizes, counts or offsets read from a file.
- **Parsers.** Use `Span`, `InlineArray`, `UniqueArray` and `Data` over raw pointers. Any `unsafe` code needs a comment explaining why it's safe.
- **Lifecycle.** A `ReaderController` runs one session at a time. Every async step checks that its session is still current before changing state, so stale work is dropped.
- **SwiftUI.**
  - Use `@Observable`, and keep fast-changing values such as `location` out of views that don't need them.
  - Don't put high-frequency values in the environment.
  - Use `.leading` and `.trailing`, never left and right.
  - Don't use soft-deprecated APIs such as `NavigationView` or the old `onChange`.
- **Localization.** User-facing strings in the package go through a String Catalog with `bundle: #bundle`. Without it, SwiftUI looks in the app's bundle and the text stays unlocalized.
- **UIKit, when needed.**
  - Avoid `UIScreen.main` and orientation checks. Use the trait collection and scene.
  - Read safe areas per edge.
- **Style.** Match the surrounding code: four-space indentation, one type per file where practical, and comments that explain why rather than what.

## Testing

- Use Swift Testing (`@Test`, `#expect`), and use XCTest only for performance metrics and UI tests.
- Build fixtures in the test, as the ZIP header in `FormatSnifferTests` does. Larger test publications go in the corpus manifest with their source and license. Never commit copyrighted books.
- Every parser bug fix comes with a test that fails without the fix.
- Never skip, disable or loosen a test to get CI green.

## Pull requests

- `main` is protected by the ruleset in `.github/rulesets/main.json`. Every change lands through a pull request, with no direct pushes, force pushes or branch deletion.
- Both CI jobs must pass on a branch that is up to date with `main`, and every review thread must be resolved before merging.
- Merge by squash only, so `main` keeps a linear history.
- Branch from `main` and keep each PR to one change.
- Fill in the PR template with "Before", "After" and "How" in plain language.
- Update the README when products, requirements or usage change, and update this file when a convention or decision changes.
- Outside contributions aren't accepted yet (see CONTRIBUTING.md). Don't merge or review PRs from people outside the maintainers.
