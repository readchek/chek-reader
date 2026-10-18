// Builds the benchmark app, runs it in the iOS Simulator and writes the results.
//
//   swift Benchmarks/Scripts/run.swift [--device "iPhone 17 Pro"] [--runs 5] [--turns 30] [--only id,id] [--readers chek,readium,pdfkit,webkit] [--out dir]
//
// Needs Xcode 27 and XcodeGen (`brew install xcodegen`). Writes
// <out>/results.json and <out>/summary.md; <out> defaults to
// Benchmarks/Results/latest, which is not committed.
//
// CI splits the work across machines with two more options:
//   --build-only        build the app into Benchmarks/.build and stop
//   --app path          run an app built earlier instead of building
//   --corpus-tool path  a compiled corpus.swift, which skips compiling the
//                       script, a step that takes minutes on a fresh machine

import Foundation

// Line-buffer output so CI logs show progress while the script runs,
// rather than everything at exit.
setvbuf(stdout, nil, _IOLBF, 0)

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
var buildOnly = false
var remaining = CommandLine.arguments.dropFirst()
while let flag = remaining.popFirst() {
    if flag == "--build-only" {
        buildOnly = true
        continue
    }
    guard flag.hasPrefix("--"), let value = remaining.popFirst() else { fail("unexpected argument \(flag)") }
    options[String(flag.dropFirst(2))] = value
}

let benchmarks = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let app = benchmarks.appendingPathComponent("ReaderBench")
let derivedData = benchmarks.appendingPathComponent(".build")
let out = URL(fileURLWithPath: options["out"] ?? benchmarks.appendingPathComponent("Results/latest").path)
let bundleID = "page.chek.bench.ReaderBench"

func build(destination: String) -> URL {
    // project.yml bundles ReaderBench/Corpus for device runs, and XcodeGen
    // keeps the reference even when the folder is missing, which fails the
    // build. An empty folder bundles nothing.
    do {
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Corpus"), withIntermediateDirectories: true)
    } catch { fail("could not create ReaderBench/Corpus: \(error)") }
    run(["xcodegen", "generate", "--spec", app.appendingPathComponent("project.yml").path])
    run([
        "xcodebuild", "build",
        "-project", app.appendingPathComponent("ReaderBench.xcodeproj").path,
        "-scheme", "ReaderBench",
        "-configuration", "Release",
        "-destination", destination,
        "-derivedDataPath", derivedData.path,
        "-quiet",
    ])
    return derivedData.appendingPathComponent("Build/Products/Release-iphonesimulator/ReaderBench.app")
}

if buildOnly {
    print("Built \(build(destination: "generic/platform=iOS Simulator").path)")
    exit(0)
}

// 1. Pick a simulator, the named one or the first iPhone on the newest iOS
// runtime, and start booting it so it finishes while the app builds.
struct DeviceList: Decodable {
    struct Device: Decodable {
        var name: String
        var udid: String
        var isAvailable: Bool
        var state: String
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
if device.state != "Booted" {
    run(["xcrun", "simctl", "boot", device.udid])
}

// 2. Corpus. It stays out of the app bundle, so the app installs quickly;
// it's copied into the app's Documents below.
let corpusDirectory = benchmarks.appendingPathComponent(".corpus")
var corpusArguments = options["corpus-tool"].map { [$0] }
    ?? ["swift", benchmarks.appendingPathComponent("Scripts/corpus.swift").path]
corpusArguments.append(corpusDirectory.path)
if let only = options["only"] { corpusArguments += ["--only", only] }
run(corpusArguments)

// 3. Build, unless CI built the app on another machine.
let product = options["app"].map { URL(fileURLWithPath: $0) }
    ?? build(destination: "platform=iOS Simulator,id=\(device.udid)")

// 4. Install, hand over the corpus and run. The app exits when it's done.
run(["xcrun", "simctl", "bootstatus", device.udid, "-b"])
run(["xcrun", "simctl", "install", device.udid, product.path])
let container = run(["xcrun", "simctl", "get_app_container", device.udid, bundleID, "data"], capture: true)
    .trimmingCharacters(in: .whitespacesAndNewlines)
let installedCorpus = URL(fileURLWithPath: container).appendingPathComponent("Documents/Corpus")
try? FileManager.default.removeItem(at: installedCorpus)
try FileManager.default.createDirectory(at: installedCorpus.deletingLastPathComponent(), withIntermediateDirectories: true)
// On APFS this is a clone, so even the large comic copies instantly.
try FileManager.default.copyItem(at: corpusDirectory, to: installedCorpus)

// Also pass the corpus's path on the Mac. The copy above is what local runs
// use; an app built on another CI machine has been seen to look in a
// different container than get_app_container reports.
var launch = ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device.udid, bundleID, "-corpus", corpusDirectory.path]
for key in ["runs", "turns", "only", "readers"] {
    if let value = options[key] { launch += ["-\(key)", value] }
}
// Cleared first, so a results file found below is always from this launch.
let containerResults = URL(fileURLWithPath: container).appendingPathComponent("Documents/results.json")
try? FileManager.default.removeItem(at: containerResults)
let console = run(launch, capture: true)
let resultsPath: String
if let line = console.split(separator: "\n").first(where: { $0.hasPrefix("BENCH_RESULTS ") }) {
    resultsPath = String(line.dropFirst("BENCH_RESULTS ".count))
} else if FileManager.default.fileExists(atPath: containerResults.path) {
    // The app writes its results before printing the line, so if the console
    // lost the line as the app exited, they're still in its container. An
    // app that stopped before writing them still fails below.
    print("warning: no BENCH_RESULTS line; using \(containerResults.path), which this launch wrote")
    resultsPath = containerResults.path
} else {
    fail("the app finished without writing results")
}

// 5. Collect and summarize.
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let results = out.appendingPathComponent("results.json")
try? FileManager.default.removeItem(at: results)
try FileManager.default.copyItem(at: URL(fileURLWithPath: resultsPath), to: results)
run(["swift", benchmarks.appendingPathComponent("Scripts/summarize.swift").path, "--out", out.appendingPathComponent("summary.md").path, results.path])
print("Results in \(out.path)")
