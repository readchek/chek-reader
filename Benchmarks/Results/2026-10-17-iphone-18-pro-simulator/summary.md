# Reader benchmark results

- Device: iPhone 18 Pro (iPhone19,2), **simulator**
- System: iOS Version 27.0 (Build 24A434)
- Screen: 402x874@3x
- Readium: 3.11.1
- Started: 2026-10-17T02:58:40Z

> Simulator numbers use the Mac's processor and memory. Use them to compare readers on the same machine and to catch regressions, not as device performance.

Times are milliseconds. Memory is the app process's footprint growth in megabytes and excludes WebKit's content processes. p95 is nearest-rank, so with few samples it's the slowest run.

## childrens-literature

Long reflowable EPUB 3 with many short chapters. EPUB, 157 KB, sha256 `e347761940e4`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Readium 3.11.1 | open | 5 | 14.9 | 58.7 | 7.4 | 58.7 | ms |  |
| Readium 3.11.1 | positions | 5 | 2.6 | 12.1 | 0.4 | 12.1 | ms | Publication.positions(), needed before the first render |
| Readium 3.11.1 | positionCount | 5 | 120 | 120 | 120 | 120 | count |  |
| Readium 3.11.1 | firstLocation | 5 | 4015 | 7206 | 3036 | 7206 | ms | attach to first locationDidChange |
| Readium 3.11.1 | contentPainted | 5 | 3648 | 6958 | 2791 | 6958 | ms | attach to two animation frames after the first document loads; the view may still be hidden |
| Readium 3.11.1 | memoryAfterOpen | 5 | 1.8 | 8.8 | 1.5 | 8.8 | MB | app process only; WebKit content processes are not counted |
| Readium 3.11.1 | pageTurn | 51 | 2.7 | 140 | 0.3 | 2271 | ms | goForward without animation until it returns |
| Readium 3.11.1 | memoryPeakTurning | 5 | 2.3 | 10.8 | 1.7 | 10.8 | MB | app process only |
| Readium 3.11.1 | relayoutFontSize | 5 | 332 | 344 | 265 | 344 | ms | font size 100% to 150% until the new size is laid out in the visible chapter |
| Readium 3.11.1 | relayoutLocationUpdate | 1 | 676 | 676 | 676 | 676 | ms | same change until Readium reports the new location |
| Readium 3.11.1 | relayoutKeepsFirstElement | 5 | yes | yes | no | yes | bool | 1 when the first visible element is the same after the change |
| Readium 3.11.1 | memoryAfterClose | 5 | 1.0 | 9.7 | 0.6 | 9.7 | MB | growth that stays after closing; app process only |
| Readium 3.11.1 | threadsAfterClose | 5 | 10 | 11 | 9 | 11 | count |  |
| WebKit floor | medianChapter.load | 5 | 3746 | 3849 | 3253 | 3849 | ms | medianChapter, 12 KB |
| WebKit floor | medianChapter.painted | 5 | 3771 | 3913 | 3263 | 3913 | ms | load to two animation frames, medianChapter, 12 KB |
| WebKit floor | medianChapter.paginate | 5 | 4.0 | 4.0 | 3.0 | 4.0 | ms | CSS columns and a forced layout, medianChapter, 12 KB |
| WebKit floor | medianChapter.pages | 5 | 1 | 1 | 1 | 1 | count |  |
| WebKit floor | medianChapter.relayoutFontSize | 5 | 8.0 | 13.0 | 4.0 | 13.0 | ms | font size to 150% and a forced layout, medianChapter, 12 KB |
| WebKit floor | medianChapter.pageTurnRoundTrip | 50 | 33.2 | 72.8 | 19.4 | 151 | ms | native call, scroll one column, two frames, reply |
| WebKit floor | largestChapter.load | 5 | 4326 | 6123 | 3688 | 6123 | ms | largestChapter, 334 KB |
| WebKit floor | largestChapter.painted | 5 | 5315 | 6143 | 3737 | 6143 | ms | load to two animation frames, largestChapter, 334 KB |
| WebKit floor | largestChapter.paginate | 5 | 100 | 120 | 48.0 | 120 | ms | CSS columns and a forced layout, largestChapter, 334 KB |
| WebKit floor | largestChapter.pages | 5 | 68 | 71 | 68 | 71 | count |  |
| WebKit floor | largestChapter.relayoutFontSize | 5 | 254 | 266 | 213 | 266 | ms | font size to 150% and a forced layout, largestChapter, 334 KB |
| WebKit floor | largestChapter.pageTurnRoundTrip | 50 | 43.8 | 88.1 | 20.5 | 99.4 | ms | native call, scroll one column, two frames, reply |

## pride-and-prejudice

Illustrated novel, 24 MB, mostly images. EPUB, 24254 KB, sha256 `d401ad6b118e`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Readium 3.11.1 | open | 5 | 31.6 | 78.3 | 18.5 | 78.3 | ms |  |
| Readium 3.11.1 | positions | 5 | 2.0 | 3.5 | 1.3 | 3.5 | ms | Publication.positions(), needed before the first render |
| Readium 3.11.1 | positionCount | 5 | 300 | 300 | 300 | 300 | count |  |
| Readium 3.11.1 | firstLocation | 5 | 3859 | 6608 | 3292 | 6608 | ms | attach to first locationDidChange |
| Readium 3.11.1 | contentPainted | 5 | 3742 | 6422 | 3140 | 6422 | ms | attach to two animation frames after the first document loads; the view may still be hidden |
| Readium 3.11.1 | memoryAfterOpen | 5 | 2.0 | 2.3 | 1.0 | 2.3 | MB | app process only; WebKit content processes are not counted |
| Readium 3.11.1 | pageTurn | 150 | 9.2 | 124 | 0.2 | 271 | ms | goForward without animation until it returns |
| Readium 3.11.1 | memoryPeakTurning | 5 | 3.3 | 3.7 | 1.5 | 3.7 | MB | app process only |
| Readium 3.11.1 | relayoutFontSize | 5 | 194 | 230 | 178 | 230 | ms | font size 100% to 150% until the new size is laid out in the visible chapter |
| Readium 3.11.1 | relayoutLocationUpdate | 5 | 532 | 572 | 507 | 572 | ms | same change until Readium reports the new location |
| Readium 3.11.1 | relayoutKeepsFirstElement | 5 | no | no | no | no | bool | 1 when the first visible element is the same after the change |
| Readium 3.11.1 | memoryAfterClose | 5 | 3.7 | 4.2 | 1.4 | 4.2 | MB | growth that stays after closing; app process only |
| Readium 3.11.1 | threadsAfterClose | 5 | 9 | 20 | 8 | 20 | count |  |
| WebKit floor | medianChapter.load | 5 | 4473 | 4919 | 3873 | 4919 | ms | medianChapter, 125 KB |
| WebKit floor | medianChapter.painted | 5 | 4701 | 4990 | 3922 | 4990 | ms | load to two animation frames, medianChapter, 125 KB |
| WebKit floor | medianChapter.paginate | 5 | 39.0 | 57.0 | 31.0 | 57.0 | ms | CSS columns and a forced layout, medianChapter, 125 KB |
| WebKit floor | medianChapter.pages | 5 | 21 | 26 | 21 | 26 | count |  |
| WebKit floor | medianChapter.relayoutFontSize | 5 | 109 | 168 | 72.0 | 168 | ms | font size to 150% and a forced layout, medianChapter, 125 KB |
| WebKit floor | medianChapter.pageTurnRoundTrip | 50 | 75.7 | 376 | 12.5 | 455 | ms | native call, scroll one column, two frames, reply |
| WebKit floor | largestChapter.load | 5 | 3744 | 4439 | 3043 | 4439 | ms | largestChapter, 164 KB |
| WebKit floor | largestChapter.painted | 5 | 3777 | 4461 | 3670 | 4461 | ms | load to two animation frames, largestChapter, 164 KB |
| WebKit floor | largestChapter.paginate | 5 | 30.0 | 46.0 | 21.0 | 46.0 | ms | CSS columns and a forced layout, largestChapter, 164 KB |
| WebKit floor | largestChapter.pages | 5 | 30 | 30 | 30 | 30 | count |  |
| WebKit floor | largestChapter.relayoutFontSize | 5 | 120 | 167 | 81.0 | 167 | ms | font size to 150% and a forced layout, largestChapter, 164 KB |
| WebKit floor | largestChapter.pageTurnRoundTrip | 50 | 114 | 434 | 32.9 | 735 | ms | native call, scroll one column, two frames, reply |

## war-and-peace

Very long text-only novel, over 1,000 printed pages. EPUB, 1789 KB, sha256 `0353122c5a55`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Readium 3.11.1 | open | 5 | 91.8 | 184 | 33.9 | 184 | ms |  |
| Readium 3.11.1 | positions | 5 | 16.4 | 29.6 | 13.4 | 29.6 | ms | Publication.positions(), needed before the first render |
| Readium 3.11.1 | positionCount | 5 | 1789 | 1789 | 1789 | 1789 | count |  |
| Readium 3.11.1 | firstLocation | 5 | 3601 | 3903 | 3508 | 3903 | ms | attach to first locationDidChange |
| Readium 3.11.1 | contentPainted | 5 | 3339 | 3641 | 3212 | 3641 | ms | attach to two animation frames after the first document loads; the view may still be hidden |
| Readium 3.11.1 | memoryAfterOpen | 5 | 1.8 | 5.5 | -6.0 | 5.5 | MB | app process only; WebKit content processes are not counted |
| Readium 3.11.1 | pageTurn | 150 | 4.8 | 612 | 0.2 | 2886 | ms | goForward without animation until it returns |
| Readium 3.11.1 | memoryPeakTurning | 5 | 6.5 | 15.0 | -3.5 | 15.0 | MB | app process only |
| Readium 3.11.1 | relayoutFontSize | 5 | 35.9 | 85.6 | 32.2 | 85.6 | ms | font size 100% to 150% until the new size is laid out in the visible chapter |
| Readium 3.11.1 | relayoutLocationUpdate | 3 | 415 | 484 | 387 | 484 | ms | same change until Readium reports the new location |
| Readium 3.11.1 | relayoutKeepsFirstElement | 5 | yes | yes | no | yes | bool | 1 when the first visible element is the same after the change |
| Readium 3.11.1 | memoryAfterClose | 5 | 3.9 | 9.9 | -7.2 | 9.9 | MB | growth that stays after closing; app process only |
| Readium 3.11.1 | threadsAfterClose | 5 | 9 | 9 | 7 | 9 | count |  |
| WebKit floor | medianChapter.load | 5 | 3792 | 4103 | 3258 | 4103 | ms | medianChapter, 9 KB |
| WebKit floor | medianChapter.painted | 5 | 3900 | 4503 | 3275 | 4503 | ms | load to two animation frames, medianChapter, 9 KB |
| WebKit floor | medianChapter.paginate | 5 | 2.0 | 6.0 | 2.0 | 6.0 | ms | CSS columns and a forced layout, medianChapter, 9 KB |
| WebKit floor | medianChapter.pages | 5 | 2 | 3 | 2 | 3 | count |  |
| WebKit floor | medianChapter.relayoutFontSize | 5 | 15.0 | 26.0 | 7.0 | 26.0 | ms | font size to 150% and a forced layout, medianChapter, 9 KB |
| WebKit floor | medianChapter.pageTurnRoundTrip | 50 | 33.4 | 102 | 4.7 | 156 | ms | native call, scroll one column, two frames, reply |
| WebKit floor | largestChapter.load | 5 | 3294 | 3498 | 3165 | 3498 | ms | largestChapter, 47 KB |
| WebKit floor | largestChapter.painted | 5 | 3358 | 3513 | 3206 | 3513 | ms | load to two animation frames, largestChapter, 47 KB |
| WebKit floor | largestChapter.paginate | 5 | 8.0 | 12.0 | 7.0 | 12.0 | ms | CSS columns and a forced layout, largestChapter, 47 KB |
| WebKit floor | largestChapter.pages | 5 | 6 | 6 | 6 | 6 | count |  |
| WebKit floor | largestChapter.relayoutFontSize | 5 | 27.0 | 51.0 | 20.0 | 51.0 | ms | font size to 150% and a forced layout, largestChapter, 47 KB |
| WebKit floor | largestChapter.pageTurnRoundTrip | 50 | 33.2 | 69.0 | 19.6 | 114 | ms | native call, scroll one column, two frames, reply |

## synthetic-pdf-1000

1,000-page text PDF. PDF, 3169 KB, sha256 `3baefacaf770`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Readium 3.11.1 | open | 5 | 6.1 | 129 | 5.9 | 129 | ms |  |
| Readium 3.11.1 | positions | 5 | 0.1 | 1.6 | 0.1 | 1.6 | ms | Publication.positions(), needed before the first render |
| Readium 3.11.1 | positionCount | 5 | 1000 | 1000 | 1000 | 1000 | count |  |
| Readium 3.11.1 | firstLocation | 5 | 31.7 | 95.7 | 25.5 | 95.7 | ms | attach to first locationDidChange |
| Readium 3.11.1 | memoryAfterOpen | 5 | 18.2 | 33.3 | -3.7 | 33.3 | MB | app process only; WebKit content processes are not counted |
| Readium 3.11.1 | pageTurn | 150 | 5.4 | 19.6 | 1.8 | 28.0 | ms | goForward without animation until it returns |
| Readium 3.11.1 | memoryPeakTurning | 5 | 34.2 | 63.6 | 2.3 | 63.6 | MB | app process only |
| Readium 3.11.1 | memoryAfterClose | 5 | 56.8 | 100.2 | 8.0 | 100.2 | MB | growth that stays after closing; app process only |
| Readium 3.11.1 | threadsAfterClose | 5 | 16 | 23 | 12 | 23 | count |  |
| PDFKit | open | 5 | 1.5 | 2.5 | 0.9 | 2.5 | ms | PDFDocument(url:) |
| PDFKit | pageCount | 5 | 1000 | 1000 | 1000 | 1000 | count |  |
| PDFKit | renderFirstPage | 5 | 6.4 | 10.4 | 4.5 | 10.4 | ms | page 1 to a screen-sized bitmap |
| PDFKit | attachView | 5 | 14.8 | 29.1 | 8.9 | 29.1 | ms | assign document, add PDFView and lay it out |
| PDFKit | renderPage | 150 | 6.4 | 25.9 | 2.0 | 147 | ms | a following page to a screen-sized bitmap |
| PDFKit | pageTurn | 150 | 10.8 | 29.2 | 3.7 | 57.2 | ms | PDFView.go(to:) and layout; tiles render after this |
| PDFKit | memoryAfterOpen | 5 | 81.9 | 165.5 | -10.9 | 165.5 | MB |  |
| PDFKit | threadsWhileOpen | 5 | 6 | 7 | 1 | 7 | count | threads added since the first run started |
| PDFKit | searchWholeDocument | 5 | 5202 | 5980 | 4820 | 5980 | ms | findString for a common word |
| PDFKit | searchMatches | 5 | 11165 | 11165 | 11165 | 11165 | count |  |
| PDFKit | memoryAfterClose | 5 | 410.9 | 458.7 | 298.8 | 458.7 | MB | growth that stays after closing |
| PDFKit | threadsAfterClose | 5 | 6 | 7 | 1 | 7 | count | threads added since the first run started; rising across runs means a leak |

## synthetic-comic-80

Large comic, about 300 MB: 80 JPEG pages at 1800 by 2700. CBZ, 293110 KB, sha256 `fdac34ede13c`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Readium 3.11.1 | open | 5 | 19.7 | 48.0 | 16.0 | 48.0 | ms |  |
| Readium 3.11.1 | positions | 5 | 0.9 | 1.1 | 0.3 | 1.1 | ms | Publication.positions(), needed before the first render |
| Readium 3.11.1 | positionCount | 5 | 80 | 80 | 80 | 80 | count |  |
| Readium 3.11.1 | firstLocation | 5 | 5635 | 11801 | 3990 | 11801 | ms | attach to first locationDidChange |
| Readium 3.11.1 | contentPainted | 5 | 1537 | 8886 | 1033 | 8886 | ms | attach to two animation frames after the first document loads; the view may still be hidden |
| Readium 3.11.1 | memoryAfterOpen | 5 | 9.8 | 135.9 | -1.3 | 135.9 | MB | app process only; WebKit content processes are not counted |
| Readium 3.11.1 | pageTurn | 150 | 373 | 683 | 124 | 3757 | ms | goForward without animation until it returns |
| Readium 3.11.1 | memoryPeakTurning | 5 | 32.0 | 199.7 | 5.7 | 199.7 | MB | app process only |
| Readium 3.11.1 | memoryAfterClose | 5 | 21.1 | 155.0 | 7.7 | 155.0 | MB | growth that stays after closing; app process only |
| Readium 3.11.1 | threadsAfterClose | 5 | 38 | 39 | 37 | 39 | count |  |