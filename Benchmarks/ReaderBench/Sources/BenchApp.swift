import UIKit

/// Runs every scenario once on launch, writes Documents/results.json, prints
/// one `BENCH_RESULTS <path>` line and exits, so a script can drive it with
/// `simctl launch --console`.
///
/// Launch arguments, all optional:
/// - `-runs N`: repetitions per fixture and reader (default 5)
/// - `-turns N`: page turns per run (default 30)
/// - `-only id,id`: fixture ids to run
@main
final class BenchApp: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = BenchSceneDelegate.self
        return configuration
    }
}

final class BenchSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window

        Task { @MainActor in
            await BenchRunner(host: host).run()
            exit(0)
        }
    }
}

@MainActor
struct BenchRunner {
    let host: UIViewController

    func run() async {
        // The runner reads this output through a pipe; line-buffer it so
        // progress shows up as it happens.
        setvbuf(stdout, nil, _IOLBF, 0)
        let defaults = UserDefaults.standard
        let runs = defaults.integer(forKey: "runs") > 0 ? defaults.integer(forKey: "runs") : 5
        let turns = defaults.integer(forKey: "turns") > 0 ? defaults.integer(forKey: "turns") : 30
        let only = defaults.string(forKey: "only").map { Set($0.split(separator: ",").map(String.init)) }

        guard
            let corpus = Bundle.main.url(forResource: "Corpus", withExtension: nil),
            let data = try? Data(contentsOf: corpus.appendingPathComponent("manifest.json")),
            let fixtures = try? JSONDecoder().decode([Fixture].self, from: data)
        else {
            print("BENCH failure: Corpus/manifest.json is missing. Run Benchmarks/Scripts/corpus.swift before building.")
            return
        }

        let recorder = Recorder(fixtures: fixtures)
        // Let launch work finish so it doesn't land in the first sample.
        await Measure.settle(2)

        let readium = ReadiumBench(host: host, recorder: recorder)
        let pdfKit = PDFKitBench(host: host, recorder: recorder)
        let webKit = WebKitFloorBench(host: host, recorder: recorder)

        for fixture in fixtures where only?.contains(fixture.id) ?? true {
            let url = corpus.appendingPathComponent(fixture.file)
            print("BENCH fixture \(fixture.id)")
            await readium.run(fixture, url: url, runs: runs, turns: turns)
            switch fixture.kind {
            case "pdf":
                await pdfKit.run(fixture, url: url, runs: runs, turns: turns)
            case "epub":
                if let publication = try? await readium.open(url) {
                    await webKit.run(fixture, publication: publication, runs: runs)
                } else {
                    recorder.fail("\(WebKitFloorBench.name) \(fixture.id): Readium could not open it to read chapters")
                }
            default:
                break
            }
        }

        do {
            let url = try recorder.write()
            print("BENCH_RESULTS \(url.path)")
        } catch {
            print("BENCH failure: could not write results: \(error)")
        }
    }
}
