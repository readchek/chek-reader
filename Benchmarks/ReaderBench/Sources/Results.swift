import Foundation
import UIKit

/// One fixture as listed in the bundled Corpus/manifest.json.
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

/// Every value one metric produced for one reader and fixture.
struct Series: Codable {
    var reader: String
    var fixture: String
    var metric: String
    var unit: String
    var values: [Double]
    var note: String?
}

struct Report: Codable {
    struct Environment: Codable {
        var device: String
        var system: String
        var screen: String
        var simulator: Bool
        var readium: String
        var startedAt: Date
    }

    var environment: Environment
    var fixtures: [Fixture]
    var series: [Series] = []
    var failures: [String] = []
}

@MainActor
final class Recorder {
    private(set) var report: Report

    init(fixtures: [Fixture]) {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        let size = screen.map { "\(Int($0.bounds.width))x\(Int($0.bounds.height))@\(Int($0.scale))x" } ?? "unknown"
        #if targetEnvironment(simulator)
        let simulator = true
        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\(UIDevice.current.name) (\($0))" } ?? UIDevice.current.name
        #else
        let simulator = false
        let device = UIDevice.current.name
        #endif
        report = Report(
            environment: .init(
                device: device,
                system: "\(UIDevice.current.systemName) \(ProcessInfo.processInfo.operatingSystemVersionString)",
                screen: size,
                simulator: simulator,
                readium: "3.11.1",
                startedAt: Date()
            ),
            fixtures: fixtures
        )
    }

    func add(_ reader: String, _ fixture: String, _ metric: String, _ unit: String, _ value: Double, note: String? = nil) {
        if let index = report.series.firstIndex(where: { $0.reader == reader && $0.fixture == fixture && $0.metric == metric }) {
            report.series[index].values.append(value)
        } else {
            report.series.append(Series(reader: reader, fixture: fixture, metric: metric, unit: unit, values: [value], note: note))
        }
    }

    func fail(_ message: String) {
        print("BENCH failure: \(message)")
        report.failures.append(message)
    }

    func write() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("results.json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
