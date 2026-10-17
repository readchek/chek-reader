#if canImport(WebKit) && canImport(SwiftUI)
import ChekReaderCore
import Foundation
import Observation
import WebKit

/// Shows reflowable publications a page at a time.
///
/// Each resource loads into its own `WebPage`, where ``ReaderScript`` lays
/// it out in columns, one screen per page. The resources before and after
/// the one on screen stay loaded off screen, so turning into the next
/// chapter shows it at once instead of waiting for a load.
///
/// Resources come from the publication through ``PublicationSchemeHandler``,
/// and every navigation is checked by ``NavigationDecider``, so content can
/// only reach the publication itself.
@MainActor
@Observable
final class WebNavigator: ReaderNavigator {
    /// One loaded resource.
    @MainActor
    final class Slot: Identifiable {
        /// The resource's reading order index.
        let id: Int
        let page: WebPage
        /// Finishes when the resource has loaded and been laid out.
        var ready: Task<Bool, Never>?
        var state: ScriptPageState?

        init(id: Int, page: WebPage) {
            self.id = id
            self.page = page
        }
    }

    /// The loaded resources, in reading order.
    private(set) var slots: [Slot] = []
    /// The reading order index of the resource on screen.
    private(set) var resourceIndex: Int?

    @ObservationIgnored private let publication: Publication
    @ObservationIgnored private weak var controller: ReaderController?
    @ObservationIgnored private let session: Int
    @ObservationIgnored private let server: PublicationServer
    @ObservationIgnored private let allowsScripts: Bool
    /// Shared by every page, so they share one set of web content processes.
    @ObservationIgnored private let dataStore = WKWebsiteDataStore.nonPersistent()
    /// Increases with every navigation, so a superseded one is dropped.
    @ObservationIgnored private var generation = 0

    private static let world = WKContentWorld.world(name: ReaderScript.contentWorld)

    init(controller: ReaderController, publication: Publication) {
        self.controller = controller
        self.publication = publication
        session = controller.session
        allowsScripts = controller.allowsPublicationScripts
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
        guard await slot.ready?.value == true, current == generation else { return false }

        var state: ScriptPageState?
        if let fragment = locator.locations.fragments.first {
            state = await call("return chekReader.goToFragment(id, generation)", ["id": fragment], in: slot)
        }
        if state == nil {
            let progression = locator.locations.progression ?? 0
            state = await call("return chekReader.goToProgression(progression, generation)", ["progression": progression], in: slot)
        }
        guard let state, current == generation else { return false }
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
        guard let slot = currentSlot, let state = slot.state else { return false }
        let position = PagePosition(resource: slot.id, page: state.page, pageCount: state.pageCount)
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
            guard let turned = await call("return chekReader.goToPage(page, generation)", ["page": page], in: slot),
                  current == generation
            else { return false }
            show(slot, state: turned)
            return true
        case .resource(let index, let atEnd):
            generation += 1
            let current = generation
            let next = self.slot(for: index)
            guard await next.ready?.value == true, current == generation else { return false }
            let script = atEnd ? "return chekReader.goToLastPage(generation)" : "return chekReader.goToPage(0, generation)"
            guard let turned = await call(script, [:], in: next), current == generation else { return false }
            show(next, state: turned)
            return true
        case .none:
            return false
        }
    }

    /// Follows a link the reader activated inside the content.
    func follow(_ href: String) async {
        guard let locator = publication.locator(for: Link(href: href)) else { return }
        _ = await go(to: locator)
    }

    // MARK: - Slots

    private var currentSlot: Slot? {
        slots.first { $0.id == resourceIndex }
    }

    /// Puts `slot` on screen, reports where the reader is, and keeps only
    /// the resources next to it loaded.
    private func show(_ slot: Slot, state: ScriptPageState) {
        slot.state = state
        resourceIndex = slot.id
        report(slot)

        let keep = (slot.id - 1)...(slot.id + 1)
        slots.removeAll { !keep.contains($0.id) }
        for neighbor in [slot.id + 1, slot.id - 1] where publication.readingOrder.indices.contains(neighbor) {
            _ = self.slot(for: neighbor)
        }
    }

    private func report(_ slot: Slot) {
        guard let state = slot.state, var locator = publication.locator(for: publication.readingOrder[slot.id]) else {
            return
        }
        locator.locations.fragments = []
        locator.locations.progression = PagePosition(resource: slot.id, page: state.page, pageCount: state.pageCount).progression
        controller?.navigator(session: session, didMoveTo: locator)
    }

    /// The slot for a resource, starting its load if it isn't loaded.
    private func slot(for index: Int) -> Slot {
        if let slot = slots.first(where: { $0.id == index }) {
            return slot
        }
        let slot = Slot(id: index, page: makePage(for: index))
        slots.append(slot)
        slots.sort { $0.id < $1.id }
        let link = publication.readingOrder[index]
        let fixed = (link.properties.layout ?? publication.metadata.layout) == .fixed
        slot.ready = Task { [weak self, weak slot] in
            guard let self, let slot else { return false }
            return await self.prepare(slot, href: link.path, fixed: fixed)
        }
        return slot
    }

    private func makePage(for index: Int) -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        if let scheme = URLScheme(PublicationServer.scheme) {
            configuration.urlSchemeHandlers[scheme] = PublicationSchemeHandler(server: server)
        }
        let content = configuration.userContentController
        content.addUserScript(WKUserScript(
            source: ReaderScript.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: Self.world
        ))
        content.add(ScriptMessageProxy(navigator: self, resource: index), contentWorld: Self.world, name: ReaderScript.messageHandler)

        let decider = NavigationDecider(allowsScripts: allowsScripts)
        decider.navigator = self
        return WebPage(configuration: configuration, navigationDecider: decider)
    }

    private func prepare(_ slot: Slot, href: String, fixed: Bool) async -> Bool {
        do {
            for try await event in slot.page.load(URLRequest(url: PublicationServer.url(for: href))) {
                if case .finished = event {
                    break
                }
            }
        } catch {
            return false
        }
        let arguments = ReaderScript.paginateArguments(fixedLayout: fixed, generation: generation)
        let script = "return await chekReader.paginate({ layout, columns, margin, verticalMargin, generation })"
        guard let state = await call(script, arguments, in: slot) else { return false }
        slot.state = state
        return true
    }

    /// Calls the reader script in `slot`'s page and reads the page state it
    /// answers with, or `nil` when the call failed or found nothing.
    private func call(_ script: String, _ arguments: [String: Any], in slot: Slot) async -> ScriptPageState? {
        var arguments = arguments
        arguments["generation"] = arguments["generation"] ?? generation
        do {
            let result = try await slot.page.callJavaScript(script, arguments: arguments, contentWorld: Self.world)
            return ScriptPageState(result)
        } catch {
            return nil
        }
    }

    // MARK: - Script messages

    /// Handles input and layout changes the reader script posts.
    fileprivate func receive(_ body: Any, from resource: Int) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        if type == "layout" {
            guard let slot = slots.first(where: { $0.id == resource }), let state = ScriptPageState(message) else { return }
            slot.state = state
            if resource == resourceIndex {
                report(slot)
            }
            return
        }
        // Only the page on screen takes input; the others are hidden.
        guard resource == resourceIndex, let input = Self.input(type: type, message: message),
              let command = PageCommand(input, readingProgression: publication.metadata.readingProgression)
        else { return }
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
    private let resource: Int

    init(navigator: WebNavigator, resource: Int) {
        self.navigator = navigator
        self.resource = resource
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        navigator?.receive(message.body, from: resource)
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
