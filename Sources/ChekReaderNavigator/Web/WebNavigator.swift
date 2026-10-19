#if canImport(WebKit) && canImport(SwiftUI)
import ChekReaderCore
import Foundation
import Observation
import WebKit

/// Shows reflowable publications a page at a time.
///
/// Each resource loads into a `WebPage`, where ``ReaderScript`` lays it out
/// in columns, one screen per page. The resource before the one on screen
/// and the two after it stay loaded off screen, so turning into the next
/// chapter shows it at once instead of waiting for a load.
///
/// Pages are reused. Creating one starts a web content process, which takes
/// seconds in the simulator, while loading another resource into a running
/// page is quick. So the navigator creates at most ``maximumSlots`` pages and
/// loads each new resource into the one holding the resource furthest away.
///
/// Resources come from the publication through ``PublicationSchemeHandler``,
/// and every navigation is checked by ``NavigationDecider``, so content can
/// only reach the publication itself.
@MainActor
@Observable
final class WebNavigator: ReaderNavigator {
    /// One web page, and the resource loaded into it.
    @MainActor
    final class Slot: Identifiable {
        /// Stays the same while the page is reused, so the view showing it does too.
        let id: Int
        let page: WebPage
        /// The reading order index of the resource loaded into the page.
        fileprivate(set) var resource: Int
        /// Increases each time the page is given another resource, so work
        /// for the one before is dropped.
        fileprivate var assignment = 0
        /// Finishes when the resource has loaded and been laid out.
        var ready: Task<Bool, Never>?
        var state: ScriptPageState?

        init(id: Int, page: WebPage, resource: Int) {
            self.id = id
            self.page = page
            self.resource = resource
        }
    }

    /// The most pages kept: the resource on screen, the one before and two after.
    static let maximumSlots = 4

    /// The web pages, in the order they were created.
    private(set) var slots: [Slot] = []
    /// The reading order index of the resource on screen.
    private(set) var resourceIndex: Int?

    @ObservationIgnored private let publication: Publication
    @ObservationIgnored private weak var controller: ReaderController?
    @ObservationIgnored private let session: Int
    @ObservationIgnored private let server: PublicationServer
    @ObservationIgnored private let allowsScripts: Bool
    @ObservationIgnored private var preferences: ReaderPreferences
    /// Shared by every page, so they share one set of web content processes.
    @ObservationIgnored private let dataStore = WKWebsiteDataStore.nonPersistent()
    /// Increases with every navigation, so a superseded one is dropped.
    @ObservationIgnored private var generation = 0
    /// Loads the resources next to the one on screen.
    @ObservationIgnored private var preloading: Task<Void, Never>?
    /// The page-turning view, when there is one. Turns then animate, and
    /// swipes are left to it.
    @ObservationIgnored weak var pager: (any BookPaging)?
    /// The size pages are laid out at, for snapshots of pages off screen.
    @ObservationIgnored var viewportSize: CGSize = .zero {
        didSet {
            if viewportSize != oldValue { snapshots.removeAll() }
        }
    }
    /// Pictures of pages for the page turn, by page.
    @ObservationIgnored private var snapshots: [BookPosition: CGImage] = [:]
    /// Snapshots being taken, so a page is only pictured once.
    @ObservationIgnored private var snapshotting: [BookPosition: Task<CGImage?, Never>] = [:]
    @ObservationIgnored private var lastSnapshot: Task<CGImage?, Never>?
    @ObservationIgnored let isRightToLeft: Bool
    private(set) var pageTransition: ReaderPreferences.PageTransition

    private static let world = WKContentWorld.world(name: ReaderScript.contentWorld)

    init(controller: ReaderController, publication: Publication) {
        self.controller = controller
        self.publication = publication
        session = controller.session
        allowsScripts = controller.allowsPublicationScripts
        preferences = controller.preferences
        pageTransition = controller.preferences.pageTransition
        isRightToLeft = publication.metadata.readingProgression == .rightToLeft
        server = PublicationServer(publication: publication, allowsScripts: controller.allowsPublicationScripts)
    }

    /// Connects to the controller and shows its current location.
    func start() async {
        guard let controller, controller.attach(self, session: session),
              let location = controller.location ?? publication.startLocator
        else { return }
        _ = await go(to: location)
    }

    // MARK: - Navigation

    func go(to locator: Locator) async -> Bool {
        guard let index = publication.readingOrderIndex(of: locator) else { return false }
        generation += 1
        let current = generation
        let slot = slot(for: index)
        guard await isReady(slot, for: index), current == generation else { return false }

        // The most precise part of the locator that still matches wins: an
        // element id, then the text, then how far through the resource.
        var state: ScriptPageState?
        if let fragment = locator.locations.fragments.first {
            state = await call("chekReader.goToFragment(id, generation)", ["id": fragment], in: slot)
        }
        if state == nil, let text = locator.text, let highlight = text.highlight, !highlight.isEmpty {
            state = await call(
                "chekReader.goToText(highlight, before, generation, near)",
                // A negative `near` means no hint, so the first match wins.
                ["highlight": highlight, "before": text.before ?? "", "near": locator.locations.progression ?? -1],
                in: slot
            )
        }
        if state == nil {
            let progression = locator.locations.progression ?? 0
            state = await call("chekReader.goToProgression(progression, generation)", ["progression": progression], in: slot)
        }
        guard let state, current == generation, slot.resource == index else { return false }
        show(slot, state: state)
        return true
    }

    func goForward() async -> Bool {
        await perform(.forward)
    }

    func goBackward() async -> Bool {
        await perform(.backward)
    }

    private func perform(_ command: PageCommand) async -> Bool {
        if let pager, let current = position {
            let target: BookPosition?
            switch command {
            case .forward: target = position(after: current)
            case .backward: target = position(before: current)
            case .firstPage: target = BookPosition(resource: current.resource, page: 0)
            case .lastPage: target = BookPosition(resource: current.resource, page: BookPosition.lastPage)
            }
            guard let target, target != current else { return false }
            await pager.turn(to: target, forward: target > current)
            return true
        }
        guard let slot = currentSlot, let state = slot.state else { return false }
        let position = PagePosition(resource: slot.resource, page: state.page, pageCount: state.pageCount)
        let turn: PageTurn
        switch command {
        case .forward:
            turn = .forward(from: position, resourceCount: publication.readingOrder.count)
        case .backward:
            turn = .backward(from: position)
        case .firstPage:
            turn = .page(0)
        case .lastPage:
            turn = .page(state.pageCount - 1)
        }

        switch turn {
        case .page(let page):
            generation += 1
            let current = generation
            guard let turned = await call("chekReader.goToPage(page, generation)", ["page": page], in: slot),
                  current == generation
            else { return false }
            show(slot, state: turned)
            return true
        case .resource(let index, let atEnd):
            generation += 1
            let current = generation
            let next = self.slot(for: index)
            guard await isReady(next, for: index), current == generation else { return false }
            let script = atEnd ? "chekReader.goToLastPage(generation)" : "chekReader.goToPage(0, generation)"
            guard let turned = await call(script, [:], in: next), current == generation, next.resource == index else {
                return false
            }
            show(next, state: turned)
            return true
        case .none:
            return false
        }
    }

    func apply(_ preferences: ReaderPreferences) async {
        self.preferences = preferences
        pageTransition = preferences.pageTransition
        snapshots.removeAll()
        generation += 1
        let current = generation
        let arguments = ReaderScript.preferenceArguments(preferences)
        // The page on screen first, so the reader sees the change soonest.
        let ordered = slots.sorted { ($0.resource == resourceIndex ? 0 : 1) < ($1.resource == resourceIndex ? 0 : 1) }
        for slot in ordered {
            let resource = slot.resource
            let ready = await isReady(slot, for: resource)
            guard current == generation else { return }
            guard ready else { continue }
            guard let state = await call("chekReader.setPreferences({ fontScale, theme, font, lineHeight, marginScale }, generation)", arguments, in: slot) else {
                continue
            }
            guard slot.resource == resource else { continue }
            slot.state = state
            if slot.resource == resourceIndex {
                report(slot)
            }
        }
    }

    /// Follows a link the reader activated inside the content.
    func follow(_ href: String) async {
        guard let locator = publication.locator(for: Link(href: href)) else { return }
        _ = await go(to: locator)
    }

    // MARK: - Turning with a pager

    /// The page on screen.
    var position: BookPosition? {
        guard let slot = currentSlot, let state = slot.state else { return nil }
        return BookPosition(resource: slot.resource, page: state.page)
    }

    /// The page after `position`, in the next resource after the last page.
    func position(after position: BookPosition) -> BookPosition? {
        let count = pageCount(of: position.resource)
        let page = resolved(position.page, count: count)
        if let count, page + 1 < count {
            return BookPosition(resource: position.resource, page: page + 1)
        }
        guard count != nil, publication.readingOrder.indices.contains(position.resource + 1) else { return nil }
        return BookPosition(resource: position.resource + 1, page: 0)
    }

    /// The page before `position`, the last of the previous resource before
    /// the first page.
    func position(before position: BookPosition) -> BookPosition? {
        let page = resolved(position.page, count: pageCount(of: position.resource))
        if page > 0 {
            return BookPosition(resource: position.resource, page: page - 1)
        }
        guard publication.readingOrder.indices.contains(position.resource - 1) else { return nil }
        return BookPosition(resource: position.resource - 1, page: BookPosition.lastPage)
    }

    /// Moves the web pages to `position` without animating; the pager has
    /// already shown the turn.
    func move(to position: BookPosition) async {
        generation += 1
        let current = generation
        let slot = slot(for: position.resource)
        guard await isReady(slot, for: position.resource), current == generation else { return }
        let script = position.page == BookPosition.lastPage
            ? "chekReader.goToLastPage(generation)"
            : "chekReader.goToPage(page, generation)"
        guard let state = await call(script, ["page": position.page], in: slot),
              current == generation, slot.resource == position.resource
        else { return }
        show(slot, state: state)
    }

    /// A picture of the page at `position`, for the page turn. Pages off
    /// screen are pictured without moving to them.
    func snapshot(of position: BookPosition) async -> CGImage? {
        if let image = snapshots[position] { return image }
        if let running = snapshotting[position] { return await running.value }
        // One at a time, since picturing a page moves a web page.
        let previous = lastSnapshot
        let task = Task { [weak self] () -> CGImage? in
            _ = await previous?.value
            guard let self else { return nil }
            return await self.takeSnapshot(of: position)
        }
        snapshotting[position] = task
        lastSnapshot = task
        let image = await task.value
        snapshotting[position] = nil
        if let image {
            snapshots[position] = image
            trimSnapshots()
        }
        return image
    }

    /// Pictures a page by moving a web page to it. A web view only draws
    /// what's on screen, so pages off screen can't be pictured in place.
    /// Other resources' pages are hidden, so they move freely; a page of the
    /// resource on screen moves under a picture of what's showing, and
    /// moves back after.
    private func takeSnapshot(of position: BookPosition) async -> CGImage? {
        let size = viewportSize
        guard size.width > 0, size.height > 0 else { return nil }
        let slot = slot(for: position.resource)
        guard await isReady(slot, for: position.resource), let state = slot.state else { return nil }
        let page = resolved(position.page, count: state.pageCount)
        if page == state.page {
            return await picture(slot)
        }
        let onScreen = slot.resource == resourceIndex
        let current = generation
        if onScreen {
            guard let showing = await picture(slot), current == generation else { return nil }
            pager?.cover(with: showing)
        }
        defer {
            if onScreen { pager?.uncover() }
        }
        guard await call("chekReader.goToPage(page, generation)", ["page": page], in: slot) != nil,
              current == generation
        else { return nil }
        let image = await picture(slot)
        if onScreen, current == generation {
            _ = await call("chekReader.goToPage(page, generation)", ["page": state.page], in: slot)
        }
        return image
    }

    private func picture(_ slot: Slot) async -> CGImage? {
        let rect = CGRect(origin: .zero, size: viewportSize)
        guard let data = try? await slot.page.exported(as: .image(region: .rect(rect))) else { return nil }
        return BookSnapshot.image(from: data)
    }

    /// Keeps only the pictures of pages near the one on screen.
    private func trimSnapshots() {
        guard snapshots.count > 8, let here = position else { return }
        snapshots = snapshots.filter { abs($0.key.resource - here.resource) <= 1 }
    }

    private func pageCount(of resource: Int) -> Int? {
        slots.first { $0.resource == resource }?.state?.pageCount
    }

    private func resolved(_ page: Int, count: Int?) -> Int {
        page == BookPosition.lastPage ? max((count ?? 1) - 1, 0) : page
    }

    // MARK: - Slots

    private var currentSlot: Slot? {
        slots.first { $0.resource == resourceIndex }
    }

    /// Puts `slot` on screen, reports where the reader is, and starts
    /// loading the resources next to it.
    private func show(_ slot: Slot, state: ScriptPageState) {
        slot.state = state
        resourceIndex = slot.resource
        report(slot)
        pager?.stopContentScrolling()

        // The next resources first, since reading usually goes forward. One
        // at a time, because new pages starting together slow each other
        // down, and the next chapter is the one the reader needs soonest.
        let origin = slot.resource
        let neighbors = [origin + 1, origin + 2, origin - 1].filter { publication.readingOrder.indices.contains($0) }
        preloading?.cancel()
        preloading = Task { [weak self] in
            // The pages either side first, so the next turn has them ready.
            if let self, let here = self.position, self.pager != nil {
                if let next = self.position(after: here) { _ = await self.snapshot(of: next) }
                if let previous = self.position(before: here) { _ = await self.snapshot(of: previous) }
            }
            for neighbor in neighbors {
                guard let self, !Task.isCancelled, self.resourceIndex == origin else { return }
                _ = await self.slot(for: neighbor).ready?.value
            }
        }
    }

    private func report(_ slot: Slot) {
        guard let state = slot.state, var locator = publication.locator(for: publication.readingOrder[slot.resource]) else {
            return
        }
        locator.locations.fragments = []
        locator.locations.progression = PagePosition(resource: slot.resource, page: state.page, pageCount: state.pageCount).progression
        locator.text = state.text
        controller?.navigator(session: session, didMoveTo: locator)
    }

    /// Whether `slot` has loaded and laid out `resource`, waiting for it if
    /// it's still loading. `false` when it failed or the page was given
    /// another resource meanwhile.
    private func isReady(_ slot: Slot, for resource: Int) async -> Bool {
        guard slot.resource == resource else { return false }
        return await slot.ready?.value == true && slot.resource == resource
    }

    /// The slot for a resource, starting its load if it isn't loaded.
    private func slot(for index: Int) -> Slot {
        if let slot = slots.first(where: { $0.resource == index }) {
            return slot
        }
        let slot: Slot
        if slots.count < Self.maximumSlots {
            slot = Slot(id: slots.count, page: makePage(slot: slots.count), resource: index)
            slots.append(slot)
        } else {
            // The page holding the resource furthest from the one on screen,
            // never the one on screen itself.
            let center = resourceIndex ?? index
            slot = slots
                .filter { $0.resource != resourceIndex }
                .max { abs($0.resource - center) < abs($1.resource - center) } ?? slots[0]
            slot.ready?.cancel()
            slot.resource = index
            slot.state = nil
        }
        slot.assignment += 1
        let assignment = slot.assignment
        let link = publication.readingOrder[index]
        let fixed = (link.properties.layout ?? publication.metadata.layout) == .fixed
        slot.ready = Task { [weak self, weak slot] in
            guard let self, let slot else { return false }
            return await self.prepare(slot, assignment: assignment, href: link.path, fixed: fixed)
        }
        return slot
    }

    private func makePage(slot: Int) -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        if let scheme = URLScheme(PublicationServer.scheme) {
            configuration.urlSchemeHandlers[scheme] = PublicationSchemeHandler(server: server)
        }
        let content = configuration.userContentController
        let fixedPaths = publication.readingOrder
            .filter { ($0.properties.layout ?? publication.metadata.layout) == .fixed }
            .map(\.path)
        content.addUserScript(WKUserScript(
            source: ReaderScript.viewportScript(fixedPaths: fixedPaths),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: Self.world
        ))
        content.addUserScript(WKUserScript(
            source: ReaderScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: Self.world
        ))
        content.add(ScriptMessageProxy(navigator: self, slot: slot), contentWorld: Self.world, name: ReaderScript.messageHandler)

        let decider = NavigationDecider(allowsScripts: allowsScripts)
        decider.navigator = self
        return WebPage(configuration: configuration, navigationDecider: decider)
    }

    private func prepare(_ slot: Slot, assignment: Int, href: String, fixed: Bool) async -> Bool {
        do {
            for try await event in slot.page.load(URLRequest(url: PublicationServer.url(for: href))) {
                if case .finished = event {
                    break
                }
            }
        } catch {
            return false
        }
        // Loading another resource into the page replaces this one.
        guard slot.assignment == assignment else { return false }
        // Preferences go first, so the first layout already uses them.
        _ = try? await slot.page.callJavaScript(
            "chekReader.setPreferences({ fontScale, theme, font, lineHeight, marginScale }, generation)",
            arguments: ReaderScript.preferenceArguments(preferences).merging(["generation": generation]) { $1 },
            contentWorld: Self.world
        )
        let arguments = ReaderScript.paginateArguments(fixedLayout: fixed, generation: generation)
        let script = "chekReader.paginate({ layout, columns, margin, verticalMargin, generation })"
        guard let state = await call(script, arguments, in: slot), slot.assignment == assignment else { return false }
        slot.state = state
        return true
    }

    /// Evaluates a reader script command in `slot`'s page and reads the page
    /// state it answers with, plus the text at the start of the page, or
    /// `nil` when the call failed or found nothing.
    private func call(_ expression: String, _ arguments: [String: Any], in slot: Slot) async -> ScriptPageState? {
        var arguments = arguments
        arguments["generation"] = arguments["generation"] ?? generation
        let script = """
            const state = await \(expression);
            if (state) {
                state.text = chekReader.locate();
            }
            return state;
            """
        do {
            let result = try await slot.page.callJavaScript(script, arguments: arguments, contentWorld: Self.world)
            return ScriptPageState(result)
        } catch {
            return nil
        }
    }

    // MARK: - Script messages

    /// Handles input and layout changes the reader script posts.
    fileprivate func receive(_ body: Any, fromSlot id: Int) {
        guard let message = body as? [String: Any], let type = message["type"] as? String,
              let slot = slots.first(where: { $0.id == id })
        else { return }
        let resource = slot.resource
        if type == "layout" {
            // A page still loading its resource may post for the one before.
            guard slot.state != nil, let state = ScriptPageState(message) else { return }
            slot.state = state
            if resource == resourceIndex {
                report(slot)
            }
            return
        }
        // Only the page on screen takes input; the others are hidden.
        guard resource == resourceIndex, let input = Self.input(type: type, message: message) else { return }
        // The page-turning view follows swipes itself.
        if pager != nil, case .swipe = input { return }
        guard let command = PageCommand(input, readingProgression: publication.metadata.readingProgression) else {
            if input == .tap(.center) {
                controller?.navigatorDidTapMiddle(session: session)
            }
            return
        }
        Task { _ = await perform(command) }
    }

    private static func input(type: String, message: [String: Any]) -> PageCommand.Input? {
        switch type {
        case "tap":
            (message["zone"] as? String).flatMap(PageCommand.Input.Zone.init(rawValue:)).map { .tap($0) }
        case "swipe":
            (message["direction"] as? String).map { .swipe(towardLeft: $0 == "left") }
        case "key":
            (message["key"] as? String).flatMap(PageCommand.Input.Key.init(rawValue:)).map { .key($0) }
        case "wheel":
            (message["direction"] as? String).map { .wheel(forward: $0 == "next") }
        default:
            nil
        }
    }
}

/// Passes the reader script's messages to the navigator without the web
/// page's content controller keeping the navigator alive.
@MainActor
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    private weak var navigator: WebNavigator?
    private let slot: Int

    init(navigator: WebNavigator, slot: Int) {
        self.navigator = navigator
        self.slot = slot
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        navigator?.receive(message.body, fromSlot: slot)
    }
}

/// Keeps the web view inside the publication: only publication URLs load,
/// links go through the navigator, and publication scripts run only when
/// the app allows them.
@MainActor
final class NavigationDecider: WebPage.NavigationDeciding {
    weak var navigator: WebNavigator?
    let allowsScripts: Bool

    init(allowsScripts: Bool) {
        self.allowsScripts = allowsScripts
    }

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        preferences.allowsContentJavaScript = allowsScripts
        guard let url = action.request.url, let href = PublicationServer.href(for: url) else {
            return .cancel
        }
        guard action.navigationType == .linkActivated else {
            return .allow
        }
        // Each page holds one resource, laid out by the reader script, so
        // links never load in place. The navigator moves to the link's page,
        // in this resource or another.
        if let navigator {
            Task { await navigator.follow(href) }
        }
        return .cancel
    }
}
#endif
