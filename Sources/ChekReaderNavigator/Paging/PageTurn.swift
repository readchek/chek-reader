import ChekReaderCore

/// Where the reader is within the reading order: a resource, and a page
/// within it.
struct PagePosition: Equatable, Sendable {
    /// The reading order index of the resource.
    var resource: Int
    /// The page within the resource, from 0.
    var page: Int
    var pageCount: Int

    /// Progress through the resource at the start of the page, from 0 to 1.
    var progression: Double {
        pageCount > 0 ? Double(page) / Double(pageCount) : 0
    }
}

/// Where turning a page leads.
enum PageTurn: Equatable, Sendable {
    /// Another page of the same resource.
    case page(Int)
    /// Another resource, opened at its first page, or at its last page when
    /// going backward into it.
    case resource(Int, atEnd: Bool)
    /// Already at the start or end of the publication.
    case none

    static func forward(from position: PagePosition, resourceCount: Int) -> PageTurn {
        if position.page + 1 < position.pageCount {
            return .page(position.page + 1)
        }
        let next = position.resource + 1
        return next < resourceCount ? .resource(next, atEnd: false) : .none
    }

    static func backward(from position: PagePosition) -> PageTurn {
        if position.page > 0 {
            return .page(min(position.page - 1, max(position.pageCount - 1, 0)))
        }
        let previous = position.resource - 1
        return previous >= 0 ? .resource(previous, atEnd: true) : .none
    }
}

/// What the reader asked for with a tap, swipe, key or scroll.
enum PageCommand: Equatable, Sendable {
    case forward
    case backward
    case firstPage
    case lastPage

    /// Input as the reader script reports it.
    enum Input: Equatable, Sendable {
        enum Zone: String, Sendable { case left, center, right }
        enum Key: String, Sendable { case left, right, up, down, next, previous, home, end }

        case tap(Zone)
        /// The direction the finger moved.
        case swipe(towardLeft: Bool)
        case key(Key)
        case wheel(forward: Bool)
    }

    /// The command for `input`, or `nil` when it isn't a page turn, such
    /// as a tap in the middle of the page.
    ///
    /// Left and right follow the reading progression: in a right-to-left
    /// publication the next page is on the left.
    init?(_ input: Input, readingProgression: Publication.ReadingProgression) {
        let rightToLeft = readingProgression == .rightToLeft
        switch input {
        case .tap(.center):
            return nil
        case .tap(let zone):
            self = (zone == .right) != rightToLeft ? .forward : .backward
        case .swipe(let towardLeft):
            // Content follows the finger, so a swipe toward the left brings
            // in the page on the right.
            self = towardLeft != rightToLeft ? .forward : .backward
        case .key(.right):
            self = rightToLeft ? .backward : .forward
        case .key(.left):
            self = rightToLeft ? .forward : .backward
        case .key(.down), .key(.next):
            self = .forward
        case .key(.up), .key(.previous):
            self = .backward
        case .key(.home):
            self = .firstPage
        case .key(.end):
            self = .lastPage
        case .wheel(let forward):
            self = forward ? .forward : .backward
        }
    }
}
