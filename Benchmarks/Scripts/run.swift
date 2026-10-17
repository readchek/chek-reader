// Builds the benchmark app, runs it in the iOS Simulator and writes the results.
//
//   swift Benchmarks/Scripts/run.swift [--device "iPhone 17 Pro"] [--runs 5] [--turns 30] [--only id,id] [--out dir]
//
// Needs Xcode 27 and XcodeGen (`brew install xcodegen`). Writes
// <out>/results.json and <out>/summary.md; <out> defaults to
// Benchmarks/Results/latest, which is not committed.

import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

/// Output collected from a pipe's handler thread.
final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    var string: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}

@discardableResult
func run(_ arguments: [String], in directory: URL? = nil, capture: Bool = false) -> String {
    print("$ \(arguments.joined(separator: " "))")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    let output = Buffer()
    if capture {
        process.standardOutput = pipe
        // Read as the process writes, so a large output can't fill the pipe and stall it.
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            output.append(chunk)
            FileHandle.standardOutput.write(chunk)
        }
    }
    do { try process.run() } catch { fail("could not run \(arguments[0]): \(error)") }
    process.waitUntilExit()
    if capture {
        pipe.fileHandleForReading.readabilityHandler = nil
        output.append(pipe.fileHandleForReading.readDataToEndOfFile())
    }
    guard process.terminationStatus == 0 else { fail("\(arguments.joined(separator: " ")) exited with \(process.terminationStatus)") }
    return output.string
}

var options: [String: String] = [:]
var remaining = CommandLine.arguments.dropFirst()
while let flag = remaining.popFirst() {
    guard flag.hasPrefix("--"), let value = remaining.popFirst() else { fail("unexpected argument \(flag)") }
    options[String(flag.dropFirst(2))] = value
}

let benchmarks = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let app = benchmarks.appendingPathComponent("ReaderBench")
let derivedData = benchmarks.appendingPathComponent(".build")
let out = URL(fileURLWithPath: options["out"] ?? benchmarks.appendingPathComponent("Results/latest").path)
let bundleID = "page.chek.bench.ReaderBench"

// 1. Corpus and project.
run(["swift", benchmarks.appendingPathComponent("Scripts/corpus.swift").path])
run(["xcodegen", "generate", "--spec", app.appendingPathComponent("project.yml").path])

// 2. Pick a simulator: the named one, or the first iPhone on the newest iOS runtime.
struct DeviceList: Decodable {
    struct Device: Decodable {
        var name: String
        var udid: String
        var isAvailable: Bool
    }

    var devices: [String: [Device]]
}

let list = try JSONDecoder().decode(
    DeviceList.self,
    from: Data(run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture: true).utf8)
)
let runtimes = list.devices.keys.filter { $0.contains("SimRuntime.iOS") }.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
let wanted = options["device"]
guard
    let device = runtimes.lazy.compactMap({ runtime in
        list.devices[runtime]?.first { device in
            device.isAvailable && (wanted.map { device.name == $0 } ?? device.name.hasPrefix("iPhone"))
        }
    }).first
else { fail("no available simulator\(wanted.map { " named \($0)" } ?? "")") }
print("Using \(device.name) (\(device.udid))")

// 3. Build.
run([
    "xcodebuild", "build",
    "-project", app.appendingPathComponent("ReaderBench.xcodeproj").path,
    "-scheme", "ReaderBench",
    "-configuration", "Release",
    "-destination", "platform=iOS Simulator,id=\(device.udid)",
    "-derivedDataPath", derivedData.path,
    "-quiet",
])
let product = derivedData.appendingPathComponent("Build/Products/Release-iphonesimulator/ReaderBench.app")

// 4. Boot, install and run. The app exits by itself when it's done.
let state = run(["xcrun", "simctl", "list", "devices", device.udid], capture: true)
if !state.contains("(Booted)") {
    run(["xcrun", "simctl", "boot", device.udid])
}
run(["xcrun", "simctl", "bootstatus", device.udid, "-b"])
run(["xcrun", "simctl", "install", device.udid, product.path])

var launch = ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device.udid, bundleID]
for key in ["runs", "turns", "only"] {
    if let value = options[key] { launch += ["-\(key)", value] }
}
let console = run(launch, capture: true)
guard let line = console.split(separator: "\n").first(where: { $0.hasPrefix("BENCH_RESULTS ") }) else {
    fail("the app finished without writing results")
}
let resultsPath = String(line.dropFirst("BENCH_RESULTS ".count))

// 5. Collect and summarize.
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let results = out.appendingPathComponent("results.json")
try? FileManager.default.removeItem(at: results)
try FileManager.default.copyItem(at: URL(fileURLWithPath: resultsPath), to: results)
run(["swift", benchmarks.appendingPathComponent("Scripts/summarize.swift").path, results.path, out.appendingPathComponent("summary.md").path])
print("Results in \(out.path)")
