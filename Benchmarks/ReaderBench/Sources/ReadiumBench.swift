import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import UIKit
import WebKit

/// Drives Readium's navigators through the same steps for every fixture.
///
/// Readiness signals, from the Readium baseline research:
/// - `firstLocation`: the first `navigator(_:locationDidChange:)`. Readium's
///   own UI test host uses it as "ready". It can trail the first paint while
///   neighbouring spreads preload.
/// - `contentPainted`: two animation frames after the first spread's
///   document loads, posted by a probe script. Readium keeps the web view
///   hidden for at least 200 ms after `load`, so this can come before the
///   page is actually visible.
@MainActor
final class ReadiumBench: NSObject {
    static let name = "Readium 3.11.1"

    private let host: UIViewController
    private let recorder: Recorder
    private let httpClient = DefaultHTTPClient()
    private lazy var assetRetriever = AssetRetriever(httpClient: httpClient)
    private lazy var opener = PublicationOpener(
        parser: DefaultPublicationParser(
            httpClient: httpClient,
            assetRetriever: assetRetriever,
            pdfFactory: DefaultPDFDocumentFactory()
        ),
        contentProtections: []
    )

    private let located = Signal()
    private let painted = Signal()
    private let paintProbe = PaintProbe()

    init(host: UIViewController, recorder: Recorder) {
        self.host = host
        self.recorder = recorder
        super.init()
        paintProbe.onPaint = { [weak self] in self?.painted.fire() }
    }

    func open(_ url: URL) async throws -> Publication {
        guard let fileURL = FileURL(url: url) else { throw BenchError("not a file URL: \(url)") }
        let asset = try await assetRetriever.retrieve(url: fileURL).get()
        return try await opener.open(asset: asset, allowUserInteraction: false, sender: nil).get()
    }

    func run(_ fixture: Fixture, url: URL, runs: Int, turns: Int) async {
        for run in 0..<runs {
            print("BENCH \(Self.name) \(fixture.id) run \(run + 1)/\(runs)")
            do {
                try await runOnce(fixture, url: url, turns: turns, measureRelayout: fixture.kind == "epub")
            } catch {
                recorder.fail("\(Self.name) \(fixture.id) run \(run): \(error)")
            }
        }
    }

    private func runOnce(_ fixture: Fixture, url: URL, turns: Int, measureRelayout: Bool) async throws {
        let id = fixture.id
        let name = Self.name
        let memoryBefore = Measure.footprintMB()

        // Held only through optionals, so dropping them before the close
        // measurement really releases the publication and navigator.
        let openStart = ContinuousClock.now
        var publication: Publication? = try await open(url)
        recorder.add(name, id, "open", "ms", Measure.milliseconds(since: openStart))

        let (positions, positionsMs) = await Measure.time { await publication!.positions() }
        recorder.add(name, id, "positions", "ms", positionsMs, note: "Publication.positions(), needed before the first render")
        if case let .success(list) = positions {
            recorder.add(name, id, "positionCount", "count", Double(list.count))
        }

        located.reset()
        painted.reset()
        var navigator: (VisualNavigator & UIViewController)? = try makeNavigator(for: publication!, kind: fixture.kind)
        let start = ContinuousClock.now
        attach(navigator!)

        let gotLocation = await located.wait(timeout: 60)
        let firstLocationMs = Measure.milliseconds(since: start)
        if gotLocation {
            recorder.add(name, id, "firstLocation", "ms", firstLocationMs, note: "attach to first locationDidChange")
        } else {
            recorder.fail("\(name) \(id): no locationDidChange within 60 s")
        }
        if fixture.kind != "pdf", await painted.wait(timeout: 5), let paintedAt = painted.firedAt {
            recorder.add(name, id, "contentPainted", "ms", Measure.milliseconds(from: start, to: paintedAt), note: "attach to two animation frames after the first document loads; the view may still be hidden")
        }

        await Measure.settle(1)
        recorder.add(name, id, "memoryAfterOpen", "MB", Measure.footprintMB() - memoryBefore, note: "app process only; WebKit content processes are not counted")

        var peak = Measure.footprintMB()
        for _ in 0..<turns {
            guard let current = navigator else { break }
            let hrefBefore = current.currentLocation?.href.string
            let (moved, turnMs) = await Measure.time { await current.goForward(options: .none) }
            guard moved else { break }
            let crossed = current.currentLocation?.href.string != hrefBefore
            recorder.add(name, id, crossed ? "pageTurnNewChapter" : "pageTurn", "ms", turnMs, note: "goForward without animation until it returns")
            peak = max(peak, Measure.footprintMB())
        }
        recorder.add(name, id, "memoryPeakTurning", "MB", peak - memoryBefore, note: "app process only")

        if measureRelayout, let epub = navigator as? EPUBNavigatorViewController {
            await Measure.settle(1)
            let before = await epub.firstVisibleElementLocator()
            let readFontSize = "getComputedStyle(document.documentElement).getPropertyValue('--USER__fontSize')"
            let initial = (try? await epub.evaluateJavaScript(readFontSize).get()) as? String ?? ""
            located.reset()
            let relayoutStart = ContinuousClock.now
            epub.submitPreferences(EPUBPreferences(fontSize: 1.5))

            // Readium applies the change as a CSS variable from JavaScript and
            // only reports a new location if the position changed, so poll for
            // the variable and then force a layout to time the relayout itself.
            var applied = false
            while Measure.milliseconds(since: relayoutStart) < 5_000 {
                let current = (try? await epub.evaluateJavaScript(readFontSize).get()) as? String ?? ""
                if current != initial {
                    _ = await epub.evaluateJavaScript("document.documentElement.scrollWidth")
                    applied = true
                    break
                }
            }
            if applied {
                recorder.add(name, id, "relayoutFontSize", "ms", Measure.milliseconds(since: relayoutStart), note: "font size 100% to 150% until the new size is laid out in the visible chapter")
                if await located.wait(timeout: 3) {
                    recorder.add(name, id, "relayoutLocationUpdate", "ms", Measure.milliseconds(since: relayoutStart), note: "same change until Readium reports the new location")
                }
                await Measure.settle(1)
                let after = await epub.firstVisibleElementLocator()
                let kept = before?.href == after?.href && before?.text.highlight == after?.text.highlight
                recorder.add(name, id, "relayoutKeepsFirstElement", "bool", kept ? 1 : 0, note: "1 when the first visible element is the same after the change")
            } else {
                recorder.fail("\(name) \(id): the font size change wasn't applied within 5 s")
            }
        }

        detach(navigator!)
        navigator = nil
        publication = nil
        await Measure.settle(2)
        recorder.add(name, id, "memoryAfterClose", "MB", Measure.footprintMB() - memoryBefore, note: "growth that stays after closing; app process only")
        recorder.add(name, id, "threadsAfterClose", "count", Double(Measure.threadCount()))
    }

    private func makeNavigator(for publication: Publication, kind: String) throws -> VisualNavigator & UIViewController {
        if kind == "pdf" {
            let navigator = try PDFNavigatorViewController(publication: publication, initialLocation: nil)
            navigator.delegate = self
            return navigator
        }
        let navigator = try EPUBNavigatorViewController(
            publication: publication,
            initialLocation: nil,
            config: EPUBNavigatorViewController.Configuration()
        )
        // Readium asks for the delegate before the view enters the hierarchy.
        navigator.delegate = self
        return navigator
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

extension ReadiumBench: EPUBNavigatorDelegate, PDFNavigatorDelegate {
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        located.fire()
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        recorder.fail("Readium navigator error: \(error)")
    }

    func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
        paintProbe.install(in: userContentController)
    }
}

/// Posts a message two animation frames after a document finishes loading.
final class PaintProbe: NSObject, WKScriptMessageHandler {
    static let handlerName = "benchPaint"
    static let source = """
        window.addEventListener('load', () => {
            requestAnimationFrame(() => requestAnimationFrame(() => {
                window.webkit.messageHandlers.\(handlerName).postMessage(performance.now());
            }));
        });
        """

    var onPaint: (@MainActor () -> Void)?

    func install(in controller: WKUserContentController) {
        // Spread views may share a controller; adding a handler twice raises.
        controller.removeScriptMessageHandler(forName: Self.handlerName)
        controller.add(self, name: Self.handlerName)
        controller.addUserScript(WKUserScript(source: Self.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { onPaint?() }
    }
}

struct BenchError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
