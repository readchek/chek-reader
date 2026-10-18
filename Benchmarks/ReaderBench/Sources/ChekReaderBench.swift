import ChekReader
import Observation
import SwiftUI
import UIKit

/// Drives Chek Reader through the same steps as ``ReadiumBench``, using only
/// the package's public API: a `ReaderController` shown by `NavigatorView`
/// in a hosting controller, as an app would.
///
/// Readiness is the controller's first location from the navigator. Every
/// navigator reports one only after its content is ready: the web navigator
/// once the chapter has loaded and been paginated, PDF once the document is
/// in its view, comics once the page is decoded.
@MainActor
final class ChekReaderBench {
    static let name = "Chek Reader"

    private let host: UIViewController
    private let recorder: Recorder
    private let changed = Signal()

    init(host: UIViewController, recorder: Recorder) {
        self.host = host
        self.recorder = recorder
        ReaderFormats.registerDefaults()
    }

    func run(_ fixture: Fixture, url: URL, runs: Int, turns: Int) async {
        for run in 0..<runs {
            print("BENCH \(Self.name) \(fixture.id) run \(run + 1)/\(runs)")
            do {
                try await runOnce(fixture, url: url, turns: turns)
                try await runPaced(fixture, url: url, turns: turns)
            } catch {
                recorder.fail("\(Self.name) \(fixture.id) run \(run): \(error)")
            }
        }
    }

    private func runOnce(_ fixture: Fixture, url: URL, turns: Int) async throws {
        let id = fixture.id
        let name = Self.name
        let memoryBefore = Measure.footprintMB()

        // Held only through optionals, so dropping them before the close
        // measurement really releases the publication and navigator.
        var controller: ReaderController? = ReaderController()
        let openStart = ContinuousClock.now
        try await controller!.open(.file(url))
        recorder.add(name, id, "open", "ms", Measure.milliseconds(since: openStart), note: "ReaderController.open until ready")
        guard var bare = controller!.publication?.startLocator else {
            throw BenchError("no reading order")
        }

        // The controller works out positions in the background after opening.
        // Waiting for them keeps their update out of the first-location timing,
        // and matches Readium, which needs them before it renders.
        let positionsStart = ContinuousClock.now
        if controller!.positions == nil {
            changed.reset()
            watch { _ = controller!.positions }
            guard await changed.wait(timeout: 60), controller!.positions != nil else {
                throw BenchError("positions not ready within 60 s")
            }
        }
        recorder.add(name, id, "positions", "ms", Measure.milliseconds(since: positionsStart), note: "after open, until ReaderController.positions is set")
        recorder.add(name, id, "positionCount", "count", Double(controller!.positions?.count ?? 0))

        // The start of the first resource with no progression, as a saved
        // location from another app might be. Every navigator's first report
        // carries a progression, so it's always a change the probe sees.
        bare.locations = Locator.Locations()
        await controller!.go(to: bare)

        changed.reset()
        watch { _ = controller!.location }
        var hosting: UIHostingController<NavigatorView>? = UIHostingController(rootView: NavigatorView(controller: controller!))
        let start = ContinuousClock.now
        attach(hosting!)
        if await changed.wait(timeout: 60), let locatedAt = changed.firedAt {
            recorder.add(name, id, "firstLocation", "ms", Measure.milliseconds(from: start, to: locatedAt), note: "attach to the first location from the navigator")
        } else {
            recorder.fail("\(name) \(id): no location within 60 s")
        }

        await Measure.settle(1)
        recorder.add(name, id, "memoryAfterOpen", "MB", Measure.footprintMB() - memoryBefore, note: "app process only; WebKit content processes are not counted")

        var peak = Measure.footprintMB()
        for _ in 0..<turns {
            let hrefBefore = controller!.location?.href
            let (moved, turnMs) = await Measure.time { await controller!.goForward() }
            guard moved else { break }
            // Each comic page is its own resource, so only reflowable text
            // has chapters to cross, as in Readium's numbers.
            let crossed = fixture.kind == "epub" && controller!.location?.href != hrefBefore
            recorder.add(name, id, crossed ? "pageTurnNewChapter" : "pageTurn", "ms", turnMs, note: "goForward until it returns")
            peak = max(peak, Measure.footprintMB())
        }
        recorder.add(name, id, "memoryPeakTurning", "MB", peak - memoryBefore, note: "app process only")

        if fixture.kind == "epub" {
            await Measure.settle(1)
            let before = controller!.location
            changed.reset()
            watch { _ = controller!.location }
            let relayoutStart = ContinuousClock.now
            await controller!.setPreferences(ReaderPreferences(fontScale: 1.5))
            recorder.add(name, id, "relayoutFontSize", "ms", Measure.milliseconds(since: relayoutStart), note: "font size 100% to 150% until setPreferences returns, which lays out every loaded chapter, up to three")
            if await changed.wait(timeout: 3), let movedAt = changed.firedAt {
                recorder.add(name, id, "relayoutLocationUpdate", "ms", Measure.milliseconds(from: relayoutStart, to: movedAt), note: "same change until the controller reports the new location")
            }
            await Measure.settle(1)
            let after = controller!.location
            let kept = before?.href == after?.href && before?.text?.highlight == after?.text?.highlight
            recorder.add(name, id, "relayoutKeepsFirstElement", "bool", kept ? 1 : 0, note: "1 when the text at the start of the page is the same after the change")
        }

        detach(hosting!)
        hosting = nil
        await controller!.close()
        controller = nil
        await Measure.settle(2)
        recorder.add(name, id, "memoryAfterClose", "MB", Measure.footprintMB() - memoryBefore, note: "growth that stays after closing; app process only")
        recorder.add(name, id, "threadsAfterClose", "count", Double(Measure.threadCount()))
    }

    /// Turns pages as a reader would, about a second each, in a session of
    /// its own so it starts as cold as ``runOnce(_:url:turns:)``. Back-to-back
    /// turns reach the next chapter before anything has had time to load
    /// ahead, so they only measure the cold path; these measure the warm one.
    private func runPaced(_ fixture: Fixture, url: URL, turns: Int) async throws {
        let id = fixture.id
        let name = Self.name
        var controller: ReaderController? = ReaderController()
        try await controller!.open(.file(url))

        changed.reset()
        watch { _ = controller!.location }
        var hosting: UIHostingController<NavigatorView>? = UIHostingController(rootView: NavigatorView(controller: controller!))
        attach(hosting!)
        guard await changed.wait(timeout: 60) else {
            throw BenchError("paced: no location within 60 s")
        }

        for _ in 0..<turns {
            await Measure.settle(1)
            let hrefBefore = controller!.location?.href
            let (moved, turnMs) = await Measure.time { await controller!.goForward() }
            guard moved else { break }
            let crossed = fixture.kind == "epub" && controller!.location?.href != hrefBefore
            recorder.add(name, id, crossed ? "pageTurnNewChapterPaced" : "pageTurnPaced", "ms", turnMs, note: "goForward until it returns, 1 s after the previous turn")
        }

        detach(hosting!)
        hosting = nil
        await controller!.close()
        controller = nil
        await Measure.settle(2)
    }

    /// Fires ``changed`` the next time a property `read` touches is about to change.
    private func watch(_ read: () -> Void) {
        withObservationTracking(read) { [changed] in
            // The controller is main-actor isolated, so changes happen there.
            MainActor.assumeIsolated { changed.fire() }
        }
    }

    private func attach(_ child: UIViewController) {
        host.addChild(child)
        child.view.frame = host.view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(child.view)
        child.didMove(toParent: host)
    }

    private func detach(_ child: UIViewController) {
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }
}
