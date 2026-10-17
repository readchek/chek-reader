#if canImport(WebKit) && canImport(SwiftUI)
import ChekReaderCore
import Foundation
import Observation
import WebKit

/// Shows reflowable publications one resource at a time in a `WebPage`.
///
/// Resources come from the publication through ``PublicationSchemeHandler``,
/// and every navigation is checked by ``NavigationDecider``, so content can
/// only reach the publication itself.
@MainActor
@Observable
final class WebNavigator: ReaderNavigator {
    @ObservationIgnored let page: WebPage
    @ObservationIgnored private let publication: Publication
    @ObservationIgnored private weak var controller: ReaderController?
    @ObservationIgnored private let session: Int
    /// Increases with every navigation, so a superseded load is dropped.
    @ObservationIgnored private var generation = 0
    /// The reading order index of the resource on screen.
    private(set) var resourceIndex: Int?

    init(controller: ReaderController, publication: Publication) {
        self.controller = controller
        self.publication = publication
        session = controller.session

        let server = PublicationServer(publication: publication, allowsScripts: controller.allowsPublicationScripts)
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        if let scheme = URLScheme(PublicationServer.scheme) {
            configuration.urlSchemeHandlers[scheme] = PublicationSchemeHandler(server: server)
        }
        let decider = NavigationDecider(allowsScripts: controller.allowsPublicationScripts)
        page = WebPage(configuration: configuration, navigationDecider: decider)
        decider.navigator = self
    }

    /// Connects to the controller and shows its current location.
    func start() async {
        guard let controller, controller.attach(self, session: session),
              let location = controller.location ?? publication.startLocator
        else { return }
        _ = await go(to: location)
    }

    func go(to locator: Locator) async -> Bool {
        guard let index = publication.readingOrderIndex(of: locator) else { return false }
        generation += 1
        let current = generation

        var href = publication.readingOrder[index].path
        if let fragment = locator.locations.fragments.first {
            href += "#" + fragment
        }
        guard await load(href) else { return false }
        guard current == generation else { return false }

        resourceIndex = index
        controller?.navigator(session: session, didMoveTo: locator)
        return true
    }

    func goForward() async -> Bool {
        await goToResource(offset: 1)
    }

    func goBackward() async -> Bool {
        await goToResource(offset: -1)
    }

    private func goToResource(offset: Int) async -> Bool {
        let target = (resourceIndex ?? 0) + offset
        guard publication.readingOrder.indices.contains(target),
              let locator = publication.locator(for: publication.readingOrder[target])
        else { return false }
        return await go(to: locator)
    }

    /// Follows a link the reader activated inside the content.
    func follow(_ href: String) async {
        guard let locator = publication.locator(for: Link(href: href)) else { return }
        _ = await go(to: locator)
    }

    /// Whether `href` is in the resource on screen, so the web view can
    /// scroll to it without a new load.
    func isOnScreen(_ href: String) -> Bool {
        guard let resourceIndex else { return false }
        return publication.readingOrder[resourceIndex].path == Link(href: href).path
    }

    private func load(_ href: String) async -> Bool {
        do {
            for try await event in page.load(URLRequest(url: PublicationServer.url(for: href))) {
                if case .finished = event {
                    return true
                }
            }
            return true
        } catch {
            return false
        }
    }
}

/// Keeps the web view inside the publication: only publication URLs load,
/// links to other resources go through the navigator, and publication
/// scripts run only when the app allows them.
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
        guard action.navigationType == .linkActivated, let navigator else {
            return .allow
        }
        if navigator.isOnScreen(href) {
            return .allow
        }
        Task { await navigator.follow(href) }
        return .cancel
    }
}
#endif
