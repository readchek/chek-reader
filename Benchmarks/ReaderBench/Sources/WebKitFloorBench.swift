import ReadiumShared
import UIKit
import WebKit

/// The cost WebKit itself puts under any reflowable reader, Chek Reader's
/// included: load one chapter from memory through a URL scheme handler,
/// paint it, split it into CSS columns and lay it out again at a new font
/// size. No reader code runs, so this is the floor to design against.
@MainActor
final class WebKitFloorBench: NSObject {
    static let name = "WebKit floor"

    private let host: UIViewController
    private let recorder: Recorder
    private let painted = Signal()
    private let finished = Signal()
    private let paintProbe = PaintProbe()

    init(host: UIViewController, recorder: Recorder) {
        self.host = host
        self.recorder = recorder
        super.init()
        paintProbe.onPaint = { [weak self] in self?.painted.fire() }
    }

    func run(_ fixture: Fixture, publication: Publication, runs: Int) async {
        let handler = MemorySchemeHandler()
        var sizes: [(href: String, bytes: Int)] = []
        for link in publication.readingOrder + publication.resources {
            guard let resource = publication.get(link), let data = try? await resource.read().get() else { continue }
            let href = link.href.removingPercentEncoding ?? link.href
            handler.resources[href] = (data, link.mediaType?.string ?? "application/octet-stream")
            if publication.readingOrder.contains(where: { $0.href == link.href }) {
                sizes.append((href, data.count))
            }
        }
        guard !sizes.isEmpty else {
            recorder.fail("\(Self.name) \(fixture.id): no readable chapters")
            return
        }
        let sorted = sizes.sorted { $0.bytes < $1.bytes }
        let chapters = [("medianChapter", sorted[sorted.count / 2]), ("largestChapter", sorted[sorted.count - 1])]

        let warmTarget = sorted[sorted.count / 2].href
        for (label, chapter) in chapters {
            for run in 0..<runs {
                print("BENCH \(Self.name) \(fixture.id) \(label) run \(run + 1)/\(runs)")
                do {
                    try await measure(fixture.id, label: label, href: chapter.href, bytes: chapter.bytes, warmHref: warmTarget, handler: handler)
                } catch {
                    recorder.fail("\(Self.name) \(fixture.id) \(label) run \(run): \(error)")
                }
            }
        }
    }

    private func measure(_ id: String, label: String, href: String, bytes: Int, warmHref: String, handler: MemorySchemeHandler) async throws {
        let name = Self.name
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: MemorySchemeHandler.scheme)
        paintProbe.install(in: configuration.userContentController)

        let webView = WKWebView(frame: host.view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        host.view.addSubview(webView)
        defer { webView.removeFromSuperview() }

        painted.reset()
        finished.reset()
        let note = "\(label), \(bytes / 1024) KB"
        let start = ContinuousClock.now
        webView.load(URLRequest(url: URL(string: "\(MemorySchemeHandler.scheme)://pub/\(href)")!))
        guard await finished.wait(timeout: 30) else { throw BenchError("load did not finish") }
        recorder.add(name, id, "\(label).load", "ms", Measure.milliseconds(since: start), note: note)
        if await painted.wait(timeout: 5), let paintedAt = painted.firedAt {
            recorder.add(name, id, "\(label).painted", "ms", Measure.milliseconds(from: start, to: paintedAt), note: "load to two animation frames, \(note)")
        }

        // A second load in the same web view reuses its content process, which
        // separates WebKit's process start-up from loading the chapter itself.
        finished.reset()
        let warmStart = ContinuousClock.now
        webView.load(URLRequest(url: URL(string: "\(MemorySchemeHandler.scheme)://pub/\(warmHref)")!))
        if await finished.wait(timeout: 30) {
            recorder.add(name, id, "\(label).warmLoad", "ms", Measure.milliseconds(since: warmStart), note: "the median chapter loaded again into the same web view after \(label)")
        }
        finished.reset()
        webView.load(URLRequest(url: URL(string: "\(MemorySchemeHandler.scheme)://pub/\(href)")!))
        guard await finished.wait(timeout: 30) else { throw BenchError("reload did not finish") }

        let paginate = """
            const t = performance.now();
            const root = document.documentElement;
            root.style.height = innerHeight + 'px';
            root.style.columnWidth = innerWidth + 'px';
            root.style.columnGap = '0px';
            root.style.overflow = 'hidden';
            const pages = Math.ceil(root.scrollWidth / innerWidth);
            return [performance.now() - t, pages];
            """
        if let result = try await webView.callAsyncJavaScript(paginate, arguments: [:], in: nil, contentWorld: .defaultClient) as? [Double], result.count == 2 {
            recorder.add(name, id, "\(label).paginate", "ms", result[0], note: "CSS columns and a forced layout, \(note)")
            recorder.add(name, id, "\(label).pages", "count", result[1])
        }

        let relayout = """
            const t = performance.now();
            const root = document.documentElement;
            root.style.fontSize = '150%';
            const pages = Math.ceil(root.scrollWidth / innerWidth);
            return [performance.now() - t, pages];
            """
        if let result = try await webView.callAsyncJavaScript(relayout, arguments: [:], in: nil, contentWorld: .defaultClient) as? [Double], result.count == 2 {
            recorder.add(name, id, "\(label).relayoutFontSize", "ms", result[0], note: "font size to 150% and a forced layout, \(note)")
        }

        let turn = """
            document.scrollingElement.scrollLeft += innerWidth;
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            return 0;
            """
        for _ in 0..<10 {
            let turnStart = ContinuousClock.now
            _ = try await webView.callAsyncJavaScript(turn, arguments: [:], in: nil, contentWorld: .defaultClient)
            recorder.add(name, id, "\(label).pageTurnRoundTrip", "ms", Measure.milliseconds(since: turnStart), note: "native call, scroll one column, two frames, reply")
        }
    }
}

extension WebKitFloorBench: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fire()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        recorder.fail("\(Self.name): navigation failed: \(error)")
    }
}

/// Serves publication resources already read into memory, so the floor
/// excludes ZIP and parsing costs.
final class MemorySchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "bench"
    var resources: [String: (data: Data, mediaType: String)] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let path = String(url.path.dropFirst())
        guard let resource = resources[path] else {
            urlSchemeTask.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
            urlSchemeTask.didFinish()
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": resource.mediaType, "Content-Length": "\(resource.data.count)"]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(resource.data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
