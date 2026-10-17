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

    /// The arguments for the script's `setPreferences` call.
    static func preferenceArguments(_ preferences: ReaderPreferences) -> [String: Any] {
        ["fontScale": preferences.fontScale, "theme": preferences.theme.rawValue]
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
