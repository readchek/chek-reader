# 18 October 2026, iPhone 18 Pro simulator, Chek Reader only

The first Chek Reader run: Chek Reader on its own, on the iPhone 18 Pro simulator, iOS 27.0 (24A434), from the `Benchmarks` workflow on GitHub's Xcode 27 runner (run 39137595794). Five runs per fixture, 30 page turns per run, each fixture on its own machine. The other readers weren't run again; the comparison below uses the [17 October baseline](../2026-10-17-iphone-18-pro-simulator), which came from the same runner type, simulator and OS build, but not the same machines, so treat small differences as noise.

Reproduce it with `swift Benchmarks/Scripts/run.swift --device "iPhone 18 Pro" --runs 5 --readers chek`. `summary.md` is the full table and `results.json` has every sample.

## Against the baseline

Medians in milliseconds, with p95 in brackets where it tells a different story. Page turns cover every turn, inside a chapter and into the next, because Readium's numbers do.

| Fixture | Metric | Chek Reader | Readium 3.11.1 |
| --- | --- | ---: | ---: |
| childrens-literature | open | 2.4 | 14.9 |
| | firstLocation | 2427 | 4015 |
| | page turn, all | 11.8 (p95 1349) | 2.7 (p95 140) |
| | relayout, page on screen | 162 | 332 |
| pride-and-prejudice | open | 25.9 | 31.6 |
| | firstLocation | 3017 | 3859 |
| | page turn, all | 17.2 (p95 1876) | 9.2 (p95 124) |
| | relayout, page on screen | 57 | 194 |
| war-and-peace | open | 25.9 | 91.8 |
| | positions | 122 | 16.4 |
| | firstLocation | 3161 | 3601 |
| | page turn, all | 2234 (p95 3083) | 4.8 (p95 612) |
| | relayout, page on screen | 5.7 | 35.9 |
| synthetic-pdf-1000 | open | 0.9 | 6.1 |
| | firstLocation | 13.2 | 31.7 |
| | pageTurn | 3.6 | 5.4 |
| | memoryAfterClose (MB) | 35.5 | 56.8 |
| synthetic-comic-80 | open | 2.6 | 19.7 |
| | firstLocation | 175 | 5635 |
| | pageTurn | 60.4 | 373 |
| | memoryAfterClose (MB) | 0.0 | 21.1 |

Chek Reader's "relayout, page on screen" is `relayoutLocationUpdate`, the time until the page on screen reports its new layout. Readium's is `relayoutFontSize`, until the new size is laid out in the visible chapter. Chek Reader's own `relayoutFontSize` waits for every loaded chapter and is much longer (173 to 1979 ms), because it includes chapters still loading.

## What stands out

- **Turning into a new chapter takes 1.9 to 2.4 s** (median `pageTurnNewChapter`), close to WebKit's cold load of a chapter in a new web view. The run turns pages back to back, faster than the next chapter preloads, so War and Peace, where 90 of 150 turns cross a chapter, is slow on almost every turn. Readium turns into the next chapter in well under a second.
- **PDF and comics are ahead of Readium on every timing.** Comics open and show their first page 30 times sooner and keep no memory after closing.
- **Positions for War and Peace take 122 ms**, against Readium's 16 ms. They're built in the background, so they don't hold up opening.
- An earlier run on the same code (39136365717) crashed on the fifth Children's Literature run without a crash report. This run didn't crash. The workflow now prints crash reports, so a repeat will show where it failed.
