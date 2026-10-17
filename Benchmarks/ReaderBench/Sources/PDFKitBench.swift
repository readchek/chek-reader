import PDFKit
import UIKit

/// Measures PDFKit directly. Preview can't be scripted, but it renders with
/// PDFKit, and so will Chek Reader's PDF module, so this is the engine floor
/// both are built on. On-device Preview numbers come from the manual protocol.
@MainActor
final class PDFKitBench {
    static let name = "PDFKit"

    private let host: UIViewController
    private let recorder: Recorder

    init(host: UIViewController, recorder: Recorder) {
        self.host = host
        self.recorder = recorder
    }

    func run(_ fixture: Fixture, url: URL, runs: Int, turns: Int) async {
        let name = Self.name
        let id = fixture.id
        let threadsAtStart = Measure.threadCount()

        for run in 0..<runs {
            print("BENCH \(name) \(id) run \(run + 1)/\(runs)")
            let memoryBefore = Measure.footprintMB()
            let openStart = ContinuousClock.now
            guard var document = PDFDocument(url: url) else {
                recorder.fail("\(name) \(id) run \(run): PDFDocument(url:) returned nil")
                return
            }
            recorder.add(name, id, "open", "ms", Measure.milliseconds(since: openStart), note: "PDFDocument(url:)")
            recorder.add(name, id, "pageCount", "count", Double(document.pageCount))

            let size = host.view.bounds.size
            let scale = host.view.window?.screen.scale ?? 3
            let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

            // Rendering a page to a screen-sized bitmap is the work PDFView does
            // for a page's first tiles, without its asynchronous tile scheduling.
            let (_, firstRenderMs) = await Measure.time { document.page(at: 0)?.thumbnail(of: pixelSize, for: .mediaBox) }
            recorder.add(name, id, "renderFirstPage", "ms", firstRenderMs, note: "page 1 to a screen-sized bitmap")

            var view: PDFView? = PDFView(frame: host.view.bounds)
            view!.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view!.displayMode = .singlePage
            view!.autoScales = true
            view!.usePageViewController(true)
            let attachStart = ContinuousClock.now
            view!.document = document
            host.view.addSubview(view!)
            view!.layoutIfNeeded()
            recorder.add(name, id, "attachView", "ms", Measure.milliseconds(since: attachStart), note: "assign document, add PDFView and lay it out")

            for index in stride(from: 1, through: min(turns, document.pageCount - 1), by: 1) {
                guard let page = document.page(at: index) else { break }
                let (_, renderMs) = await Measure.time { page.thumbnail(of: pixelSize, for: .mediaBox) }
                recorder.add(name, id, "renderPage", "ms", renderMs, note: "a following page to a screen-sized bitmap")
                let (_, turnMs) = await Measure.time {
                    view!.go(to: page)
                    view!.layoutIfNeeded()
                }
                recorder.add(name, id, "pageTurn", "ms", turnMs, note: "PDFView.go(to:) and layout; tiles render after this")
            }

            // Give iOS 26's automatic page analysis time to start, since that
            // is where developers report leaked memory and threads.
            await Measure.settle(3)
            recorder.add(name, id, "memoryAfterOpen", "MB", Measure.footprintMB() - memoryBefore)
            recorder.add(name, id, "threadsWhileOpen", "count", Double(Measure.threadCount() - threadsAtStart), note: "threads added since the first run started")

            // Only the count is kept: selections retain the document.
            let (matches, searchMs) = await Measure.time {
                document.findString("silver", withOptions: [.caseInsensitive]).count
            }
            recorder.add(name, id, "searchWholeDocument", "ms", searchMs, note: "findString for a common word")
            recorder.add(name, id, "searchMatches", "count", Double(matches))

            view!.removeFromSuperview()
            view = nil
            document = PDFDocument()
            await Measure.settle(2)
            recorder.add(name, id, "memoryAfterClose", "MB", Measure.footprintMB() - memoryBefore, note: "growth that stays after closing")
            recorder.add(name, id, "threadsAfterClose", "count", Double(Measure.threadCount() - threadsAtStart), note: "threads added since the first run started; rising across runs means a leak")
        }
    }
}
