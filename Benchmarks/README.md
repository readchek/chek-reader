# Benchmarks

Measures Chek Reader against the readers it has to match or beat: the Readium Swift toolkit, Apple Books, Apple Preview (through PDFKit) and Chibi Manga's current renderer. Every comparison uses the same files, device, OS build and steps, and lists them next to the numbers.

Nothing in the package depends on this folder. The benchmark app links Readium only to measure it.

## What's here

| Path | Contents |
| --- | --- |
| `corpus.json` | The fixtures, with their source, license and checksum. Files are fetched or generated at run time, never committed |
| `Scripts/corpus.swift` | Downloads the public-domain fixtures and draws the synthetic PDF and comic, into `.corpus` |
| `Scripts/run.swift` | Builds the app, runs it in the iOS Simulator and writes `results.json` and `summary.md` |
| `Scripts/summarize.swift` | Merges one or more `results.json` files and writes a Markdown table |
| `ReaderBench/` | The benchmark host app, generated with XcodeGen |
| `Results/` | Published runs, one folder per run |

## Running it

On a Mac with Xcode 27:

```sh
brew install xcodegen
swift Benchmarks/Scripts/run.swift                      # first iPhone on the newest runtime, 5 runs
swift Benchmarks/Scripts/run.swift --device "iPad Pro 13-inch (M5)" --runs 10
swift Benchmarks/Scripts/run.swift --only war-and-peace --turns 60
swift Benchmarks/Scripts/run.swift --readers chek         # one reader on its own
```

`--readers` takes any of `chek`, `readium`, `pdfkit` and `webkit`, comma separated, and defaults to all of them. Use it to measure one reader without running the others again, then compare with a published run from the same machine. The workflow has the same option.

Results land in `Benchmarks/Results/latest`. The script boots the simulator while the app builds, and copies the corpus into the app's Documents folder after installing, so the large files never go through the app bundle.

The `Benchmarks` workflow runs the same script on demand: start it from the Actions tab with **Run workflow**. It never runs on its own, because a full run takes long enough to hold up a pull request. One job builds the app, with the build cached between runs. Then each fixture gets its own job on its own machine, so they run in parallel without competing for one processor. A last job merges the results; its summary appears on the run page and in the log. Because fixtures run on different machines, compare readers within a fixture, not across fixtures.

To run on a physical device, write the corpus where the app bundles it with `swift Benchmarks/Scripts/corpus.swift Benchmarks/ReaderBench/Corpus`, then open the generated `ReaderBench.xcodeproj`, choose your team, and run the `ReaderBench` scheme. The app prints `BENCH_RESULTS` with the path of its results when it's done.

## What it measures

Each fixture runs through every reader that can open it, `--runs` times, each run starting from a closed publication.

| Metric | Readers | What it is |
| --- | --- | --- |
| `open` | Chek Reader, Readium, PDFKit | Parse the file into a publication or document. For Chek Reader, `ReaderController.open` until it's ready |
| `positions` | Chek Reader, Readium | Build the positions list. Readium waits for it before it renders; Chek Reader builds it in the background after opening, and the run waits for it before showing the navigator |
| `firstLocation` | Chek Reader, Readium | From adding the navigator to the window to its first location. For Readium that's `locationDidChange`, which its own UI tests treat as ready. Chek Reader's navigators report it once the chapter is loaded and paginated, the PDF is in its view, or the comic page is decoded |
| `contentPainted` | Readium | Two animation frames after the first document's `load` event. Readium keeps the page hidden for at least 200 ms after that, so this is earlier than visible |
| `pageTurn`, `pageTurnNewChapter` | Chek Reader, Readium | `goForward` without animation until it returns, split by whether the turn entered a new chapter |
| `relayoutFontSize` | Chek Reader, Readium | Font size from 100% to 150% until it's laid out. Readium's covers the visible chapter. Chek Reader's waits for `setPreferences`, which lays out every loaded chapter, up to three |
| `relayoutLocationUpdate` | Chek Reader, Readium | The same change until the reader reports a new location, when it does |
| `relayoutKeepsFirstElement` | Chek Reader, Readium | Whether the first visible element, or for Chek Reader the text at the start of the page, is the same after that change |
| `renderFirstPage`, `renderPage` | PDFKit | Draw a page to a screen-sized bitmap, the work behind PDFView's first tiles |
| `pageTurn` | PDFKit | `PDFView.go(to:)` and layout. Tiles render after this, so it's a lower bound |
| `searchWholeDocument` | PDFKit | `findString` across the whole document |
| `*.load`, `*.painted` | WebKit floor | Load one chapter from memory in a new `WKWebView`, and paint it. This includes starting WebKit's content process |
| `*.warmLoad` | WebKit floor | Load a chapter into a web view that's already running, so no process start-up |
| `*.paginate`, `*.relayoutFontSize` | WebKit floor | Split the chapter into CSS columns, then lay it out again at 150%, timed inside the page |
| `*.pageTurnRoundTrip` | WebKit floor | A native call that scrolls one column, waits two frames and replies |
| `memory*`, `threads*` | All | The app process's footprint growth and thread count |

The WebKit floor is what any web-based reader pays before its own code runs, Chek Reader's included. Its chapters come from the same EPUBs: the median-sized and the largest chapter of each.

Memory counts the app process only. WebKit renders in separate content processes, so web-based readers look smaller than they are; compare those with Instruments on a device.

## What the simulator can and can't tell you

Simulator runs use the Mac's processor, GPU and memory. They're good for comparing readers in the same run and for catching regressions between commits. They aren't device performance, and only device runs are published as performance claims (see Validation in the design doc). Frame pacing and hitches need a device and Instruments.

## Apple Books and Preview

Neither can be scripted or profiled from outside, so they're measured by hand with a high-speed camera. Follow this protocol so results can be repeated:

1. **Fixtures.** Use the files from `corpus.json` and record their checksums.
2. **Device state.** Fixed brightness, Low Power Mode off, battery above 80% and charging, airplane mode on so sync stays off. Record the ProMotion and Limit Frame Rate settings. Restart, then wait two minutes.
3. **Camera.** Film the finger and the screen together at 240 fps, for example with an iPhone in slow motion. On-device screen recording tops out at 60 fps and can't see the touch, so it can't measure latency.
4. **Open.** Start at the beginning of the book in every app, because Books restores the last position. Time from the frame where the tap lands to the first frame where the page's text is fully drawn. Do 10 cold opens (app force-quit first) and 10 warm opens.
5. **Page turn.** Time from touch-down to the first frame showing the next page, over 30 turns. Repeat with Reduce Motion on, so animation length doesn't hide input latency.
6. **Relayout.** Time from tapping the larger font size to stable text, and note whether the position moved.
7. **Memory on the Mac.** `sudo footprint -p Books --sample 0.5 -j books.json` during open, 50 turns and close.
8. **Scoring.** Two people pick the frames independently. Report the median and p90 with n. Each measurement is accurate to about ±8 ms at 240 fps, plus up to one refresh of display jitter, so differences under about 15 ms are noise.
9. **Publish.** Device, OS build, app version, fixture checksums and the raw frame numbers.

Measure Chek Reader the same way when it's compared with Books or Preview, so all three are timed on equal terms.

## Adding a reader

Add a `<Reader>Bench.swift` in `ReaderBench/Sources` with the same metric names where they apply, link it in `project.yml`, call it from `BenchRunner`, and give it a name for `--readers`. `ChekReaderBench.swift` is the Chek Reader one: it links the package from this checkout and uses only its public API, a `ReaderController` shown by `NavigatorView`, as an app would.
