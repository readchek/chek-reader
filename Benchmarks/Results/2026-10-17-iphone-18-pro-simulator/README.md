# 17 October 2026, iPhone 18 Pro simulator

The first baseline: Readium 3.11.1, PDFKit and the WebKit floor on the iPhone 18 Pro simulator, iOS 27.0 (24A434), from the `Benchmarks` workflow on GitHub's Xcode 27 runner (run 38996400475). Five runs per fixture, 30 page turns per run, all fixtures on one machine.

Reproduce it with `swift Benchmarks/Scripts/run.swift --device "iPhone 18 Pro" --runs 5`. `summary.md` is the table and `results.json` has every sample.
