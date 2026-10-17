// Turns one or more ReaderBench results.json files into a Markdown summary.
//
//   swift Benchmarks/Scripts/summarize.swift [--out summary.md] [--merged results.json] results.json...
//
// Several files, such as one per fixture from parallel CI jobs, are merged
// first; --merged writes that combined file. The summary goes to standard
// output when --out is missing.

import Foundation

struct Report: Codable {
    struct Environment: Codable {
        var device: String
        var system: String
        var screen: String
        var simulator: Bool
        var readium: String
        var startedAt: String
    }

    struct Fixture: Codable {
        var id: String
        var kind: String
        var role: String
        var file: String
        var bytes: Int
        var sha256: String
        var source: String
        var license: String
    }

    struct Series: Codable {
        var reader: String
        var fixture: String
        var metric: String
        var unit: String
        var values: [Double]
        var note: String?
    }

    var environment: Environment
    var fixtures: [Fixture]
    var series: [Series]
    var failures: [String]
}

/// Nearest-rank percentile, so every reported value is one that was measured.
func percentile(_ sorted: [Double], _ p: Double) -> Double {
    let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
    return sorted[max(0, min(sorted.count - 1, rank - 1))]
}

func format(_ value: Double, _ unit: String) -> String {
    switch unit {
    case "count": return String(Int(value.rounded()))
    case "bool": return value >= 0.5 ? "yes" : "no"
    case "MB": return String(format: "%.1f", value)
    default: return value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

var outPath: String?
var mergedPath: String?
var inputs: [String] = []
var remaining = CommandLine.arguments.dropFirst()
while let argument = remaining.popFirst() {
    switch argument {
    case "--out": outPath = remaining.popFirst()
    case "--merged": mergedPath = remaining.popFirst()
    default: inputs.append(argument)
    }
}
guard !inputs.isEmpty else {
    FileHandle.standardError.write(Data("usage: summarize.swift [--out summary.md] [--merged results.json] results.json...\n".utf8))
    exit(1)
}

let reports = try inputs.map { try JSONDecoder().decode(Report.self, from: Data(contentsOf: URL(fileURLWithPath: $0))) }
var report = reports[0]
for other in reports.dropFirst() {
    report.fixtures += other.fixtures.filter { fixture in !report.fixtures.contains { $0.id == fixture.id } }
    report.series += other.series
    report.failures += other.failures
}
if let mergedPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: URL(fileURLWithPath: mergedPath))
}
let environment = report.environment

var lines: [String] = []
lines.append("# Reader benchmark results")
lines.append("")
lines.append("- Device: \(environment.device)\(environment.simulator ? ", **simulator**" : "")")
lines.append("- System: \(environment.system)")
lines.append("- Screen: \(environment.screen)")
lines.append("- Readium: \(environment.readium)")
lines.append("- Started: \(environment.startedAt)")
if reports.count > 1 {
    lines.append("- Merged from \(reports.count) runs, one per fixture, each on its own CI machine. Compare readers within a fixture, not across fixtures.")
}
if environment.simulator {
    lines.append("")
    lines.append("> Simulator numbers use the Mac's processor and memory. Use them to compare readers on the same machine and to catch regressions, not as device performance.")
}
lines.append("")
lines.append("Times are milliseconds. Memory is the app process's footprint growth in megabytes and excludes WebKit's content processes. p95 is nearest-rank, so with few samples it's the slowest run.")

for fixture in report.fixtures {
    let rows = report.series.filter { $0.fixture == fixture.id }
    guard !rows.isEmpty else { continue }
    lines.append("")
    lines.append("## \(fixture.id)")
    lines.append("")
    lines.append("\(fixture.role). \(fixture.kind.uppercased()), \(fixture.bytes / 1024) KB, sha256 `\(fixture.sha256.prefix(12))`.")
    lines.append("")
    lines.append("| Reader | Metric | n | Median | p95 | Min | Max | Unit | Measures |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |")
    for series in rows {
        let sorted = series.values.sorted()
        guard !sorted.isEmpty else { continue }
        let unit = series.unit
        lines.append(
            "| \(series.reader) | \(series.metric) | \(sorted.count) | \(format(percentile(sorted, 50), unit)) | \(format(percentile(sorted, 95), unit)) | \(format(sorted.first!, unit)) | \(format(sorted.last!, unit)) | \(unit) | \(series.note ?? "") |"
        )
    }
}

if !report.failures.isEmpty {
    lines.append("")
    lines.append("## Failures")
    lines.append("")
    for failure in report.failures {
        lines.append("- \(failure)")
    }
}

let markdown = lines.joined(separator: "\n") + "\n"
if let outPath {
    try markdown.write(to: URL(fileURLWithPath: outPath), atomically: true, encoding: .utf8)
} else {
    print(markdown, terminator: "")
}
