import ChekReaderCore
import Foundation

/// The reader's own script, compiled from `Scripts/Reader` and bundled with
/// this target.
///
/// It runs in its own content world, so publication scripts can't reach it,
/// and it runs whether or not publication scripts are allowed.
enum ReaderScript {
    /// The content world the script runs in.
    static let contentWorld = "ChekReader"
    /// The message handler the script posts input and layout changes to.
    static let messageHandler = "chekReader"

    /// The script's source.
    static let source: String = {
        guard let url = Bundle.module.url(forResource: "reader", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("reader.js is missing from the ChekReaderNavigator bundle. Run `npm run build` in Scripts/Reader.")
            return ""
        }
        return source
    }()

    /// The viewport reflowable resources are laid out in.
    static let deviceViewport = "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"

    /// A script that runs before each resource's own markup and gives
    /// reflowable resources a device-width viewport.
    ///
    /// Most EPUBs have no viewport tag, and without one WebKit on iOS lays a
    /// page out 980 pixels wide and scales it down, so text comes out tiny
    /// with hairline margins. It has to be in place before the first layout,
    /// since a viewport added later doesn't always take effect. Fixed-layout
    /// resources, at `fixedPaths`, keep their own viewport, which says how
    /// big their page is.
    static func viewportScript(fixedPaths: some Sequence<String>) -> String {
        let paths = fixedPaths.map { "/" + $0 }.sorted()
        let json = (try? JSONSerialization.data(withJSONObject: paths)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
            (() => {
                const fixed = new Set(\(json));
                if (fixed.has(decodeURIComponent(location.pathname))) {
                    return;
                }
                const meta = document.createElement("meta");
                meta.name = "viewport";
                meta.content = "\(deviceViewport)";
                document.documentElement.appendChild(meta);
            })();
            """
    }

    /// The arguments for the script's `setPreferences` call.
    static func preferenceArguments(_ preferences: ReaderPreferences) -> [String: Any] {
        [
            "fontScale": preferences.fontScale,
            "theme": preferences.theme.rawValue,
            "font": preferences.font.rawValue,
            // Zero keeps the publication's line height.
            "lineHeight": preferences.lineHeight ?? 0,
            "marginScale": preferences.marginScale,
        ]
    }

    /// The options for the script's `paginate` call. Each key becomes a
    /// variable in the called function.
    static func paginateArguments(fixedLayout: Bool, generation: Int) -> [String: Any] {
        [
            "layout": fixedLayout ? "fixed" : "reflowable",
            // Zero lets the script choose one or two columns from the viewport.
            "columns": 0,
            "margin": 24,
            "verticalMargin": 32,
            "generation": generation,
        ]
    }
}

/// The page state the reader script answers every command with.
struct ScriptPageState: Equatable, Sendable {
    var page: Int
    var pageCount: Int
    var generation: Int
    /// The text at the start of the page, which finds the same place
    /// again after the layout changes.
    var text: Locator.Text?

    /// Reads the script's reply, which arrives as a dictionary of numbers.
    init?(_ value: Any?) {
        guard let dictionary = value as? [String: Any],
              let page = Self.integer(dictionary["page"]),
              let pageCount = Self.integer(dictionary["pageCount"]),
              pageCount > 0
        else { return nil }
        self.page = max(0, min(page, pageCount - 1))
        self.pageCount = pageCount
        self.generation = Self.integer(dictionary["generation"]) ?? 0
        if let text = dictionary["text"] as? [String: Any], let highlight = text["highlight"] as? String, !highlight.isEmpty {
            self.text = Locator.Text(
                before: text["before"] as? String,
                highlight: highlight,
                after: text["after"] as? String
            )
        }
    }

    /// JavaScript numbers arrive as `NSNumber` from WebKit, and as Swift
    /// numbers when built in tests.
    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            value
        case let value as Double where value.isFinite && abs(value) < 1e9:
            Int(value)
        case let value as NSNumber where value.doubleValue.isFinite && abs(value.doubleValue) < 1e9:
            // A Double that failed the check above also bridges to
            // NSNumber, so the bounds are checked again here.
            value.intValue
        default:
            nil
        }
    }
}
