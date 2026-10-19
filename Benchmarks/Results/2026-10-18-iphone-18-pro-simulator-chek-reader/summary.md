# Reader benchmark results

- Device: iPhone 18 Pro (iPhone19,2), **simulator**
- System: iOS Version 27.0 (Build 24A434)
- Screen: 402x874@3x
- Readium: 3.11.1
- Started: 2026-10-18T14:53:12Z
- Merged from 5 runs, one per fixture, each on its own CI machine. Compare readers within a fixture, not across fixtures.

> Simulator numbers use the Mac's processor and memory. Use them to compare readers on the same machine and to catch regressions, not as device performance.

Times are milliseconds. Memory is the app process's footprint growth in megabytes and excludes WebKit's content processes. p95 is nearest-rank, so with few samples it's the slowest run.

## childrens-literature

Long reflowable EPUB 3 with many short chapters. EPUB, 157 KB, sha256 `e347761940e4`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Chek Reader | open | 5 | 2.4 | 7.4 | 2.1 | 7.4 | ms | ReaderController.open until ready |
| Chek Reader | positions | 5 | 0.2 | 0.2 | 0.1 | 0.2 | ms | after open, until ReaderController.positions is set |
| Chek Reader | positionCount | 5 | 349 | 349 | 349 | 349 | count |  |
| Chek Reader | firstLocation | 5 | 2427 | 5393 | 2262 | 5393 | ms | attach to the first location from the navigator |
| Chek Reader | memoryAfterOpen | 5 | 0.4 | 8.6 | 0.2 | 8.6 | MB | app process only; WebKit content processes are not counted |
| Chek Reader | pageTurnNewChapter | 10 | 1903 | 2775 | 1217 | 2775 | ms | goForward until it returns |
| Chek Reader | pageTurn | 140 | 11.6 | 65.7 | 4.7 | 240 | ms | goForward until it returns |
| Chek Reader | memoryPeakTurning | 5 | 0.8 | 11.4 | 0.3 | 11.4 | MB | app process only |
| Chek Reader | relayoutFontSize | 5 | 173 | 251 | 170 | 251 | ms | font size 100% to 150% until setPreferences returns, which lays out every loaded chapter, up to three |
| Chek Reader | relayoutLocationUpdate | 5 | 162 | 180 | 147 | 180 | ms | same change until the controller reports the new location |
| Chek Reader | relayoutKeepsFirstElement | 5 | no | no | no | no | bool | 1 when the text at the start of the page is the same after the change |
| Chek Reader | memoryAfterClose | 5 | 0.3 | 10.5 | -0.0 | 10.5 | MB | growth that stays after closing; app process only |
| Chek Reader | threadsAfterClose | 5 | 8 | 13 | 8 | 13 | count |  |

## pride-and-prejudice

Illustrated novel, 24 MB, mostly images. EPUB, 24254 KB, sha256 `d401ad6b118e`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Chek Reader | open | 5 | 25.9 | 37.7 | 23.0 | 37.7 | ms | ReaderController.open until ready |
| Chek Reader | positions | 5 | 0.6 | 0.8 | 0.5 | 0.8 | ms | after open, until ReaderController.positions is set |
| Chek Reader | positionCount | 5 | 853 | 853 | 853 | 853 | count |  |
| Chek Reader | firstLocation | 5 | 3017 | 6924 | 2634 | 6924 | ms | attach to the first location from the navigator |
| Chek Reader | memoryAfterOpen | 5 | 0.5 | 8.6 | 0.4 | 8.6 | MB | app process only; WebKit content processes are not counted |
| Chek Reader | pageTurn | 140 | 16.3 | 155 | 1.6 | 577 | ms | goForward until it returns |
| Chek Reader | pageTurnNewChapter | 10 | 2143 | 2910 | 1620 | 2910 | ms | goForward until it returns |
| Chek Reader | memoryPeakTurning | 5 | 2.2 | 12.8 | 0.4 | 12.8 | MB | app process only |
| Chek Reader | relayoutFontSize | 5 | 1979 | 2967 | 1446 | 2967 | ms | font size 100% to 150% until setPreferences returns, which lays out every loaded chapter, up to three |
| Chek Reader | relayoutLocationUpdate | 5 | 57.2 | 77.8 | 49.7 | 77.8 | ms | same change until the controller reports the new location |
| Chek Reader | relayoutKeepsFirstElement | 5 | no | no | no | no | bool | 1 when the text at the start of the page is the same after the change |
| Chek Reader | memoryAfterClose | 5 | 0.5 | 10.2 | -0.0 | 10.2 | MB | growth that stays after closing; app process only |
| Chek Reader | threadsAfterClose | 5 | 9 | 10 | 9 | 10 | count |  |

## synthetic-comic-80

Large comic, about 300 MB: 80 JPEG pages at 1800 by 2700. CBZ, 293110 KB, sha256 `9e7f4436ca23`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Chek Reader | open | 5 | 2.6 | 3.2 | 2.0 | 3.2 | ms | ReaderController.open until ready |
| Chek Reader | positions | 5 | 0.8 | 0.8 | 0.7 | 0.8 | ms | after open, until ReaderController.positions is set |
| Chek Reader | positionCount | 5 | 80 | 80 | 80 | 80 | count |  |
| Chek Reader | firstLocation | 5 | 175 | 323 | 139 | 323 | ms | attach to the first location from the navigator |
| Chek Reader | memoryAfterOpen | 5 | 0.2 | 3.8 | 0.1 | 3.8 | MB | app process only; WebKit content processes are not counted |
| Chek Reader | pageTurn | 150 | 60.4 | 166 | 0.0 | 223 | ms | goForward until it returns |
| Chek Reader | memoryPeakTurning | 5 | 41.1 | 44.8 | 41.1 | 44.8 | MB | app process only |
| Chek Reader | memoryAfterClose | 5 | 0.0 | 3.5 | 0.0 | 3.5 | MB | growth that stays after closing; app process only |
| Chek Reader | threadsAfterClose | 5 | 7 | 7 | 7 | 7 | count |  |

## synthetic-pdf-1000

1,000-page text PDF. PDF, 3169 KB, sha256 `9807cd887413`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Chek Reader | open | 5 | 0.9 | 16.4 | 0.9 | 16.4 | ms | ReaderController.open until ready |
| Chek Reader | positions | 5 | 0.1 | 0.2 | 0.1 | 0.2 | ms | after open, until ReaderController.positions is set |
| Chek Reader | positionCount | 5 | 1000 | 1000 | 1000 | 1000 | count |  |
| Chek Reader | firstLocation | 5 | 13.2 | 149 | 9.9 | 149 | ms | attach to the first location from the navigator |
| Chek Reader | memoryAfterOpen | 5 | 21.3 | 27.3 | 8.3 | 27.3 | MB | app process only; WebKit content processes are not counted |
| Chek Reader | pageTurn | 150 | 3.6 | 21.3 | 1.1 | 24.4 | ms | goForward until it returns |
| Chek Reader | memoryPeakTurning | 5 | 29.9 | 33.3 | 16.5 | 33.3 | MB | app process only |
| Chek Reader | memoryAfterClose | 5 | 35.5 | 94.5 | -23.7 | 94.5 | MB | growth that stays after closing; app process only |
| Chek Reader | threadsAfterClose | 5 | 18 | 22 | 12 | 22 | count |  |

## war-and-peace

Very long text-only novel, over 1,000 printed pages. EPUB, 1789 KB, sha256 `0353122c5a55`.

| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Chek Reader | open | 5 | 25.9 | 56.8 | 22.2 | 56.8 | ms | ReaderController.open until ready |
| Chek Reader | positions | 5 | 122 | 208 | 103 | 208 | ms | after open, until ReaderController.positions is set |
| Chek Reader | positionCount | 5 | 4118 | 4118 | 4118 | 4118 | count |  |
| Chek Reader | firstLocation | 5 | 3161 | 7209 | 2257 | 7209 | ms | attach to the first location from the navigator |
| Chek Reader | memoryAfterOpen | 5 | 0.9 | 9.0 | 0.3 | 9.0 | MB | app process only; WebKit content processes are not counted |
| Chek Reader | pageTurn | 60 | 16.9 | 36.4 | 1.9 | 200 | ms | goForward until it returns |
| Chek Reader | pageTurnNewChapter | 90 | 2426 | 3391 | 1224 | 5480 | ms | goForward until it returns |
| Chek Reader | memoryPeakTurning | 5 | 1.7 | 13.1 | 0.9 | 13.1 | MB | app process only |
| Chek Reader | relayoutFontSize | 5 | 1311 | 1587 | 1275 | 1587 | ms | font size 100% to 150% until setPreferences returns, which lays out every loaded chapter, up to three |
| Chek Reader | relayoutLocationUpdate | 2 | 5.7 | 8.9 | 5.7 | 8.9 | ms | same change until the controller reports the new location |
| Chek Reader | relayoutKeepsFirstElement | 5 | yes | yes | no | yes | bool | 1 when the text at the start of the page is the same after the change |
| Chek Reader | memoryAfterClose | 5 | 0.6 | 10.5 | 0.3 | 10.5 | MB | growth that stays after closing; app process only |
| Chek Reader | threadsAfterClose | 5 | 8 | 10 | 7 | 10 | count |  |
