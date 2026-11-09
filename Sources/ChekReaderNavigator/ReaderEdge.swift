/// An end of a publication, past its pages.
///
/// Apps that read a series give each end a page of its own, such as one
/// naming the next chapter, with `readerEdgePages(start:end:content:)`.
/// The reader turns onto it as it turns onto any page, and turning on past
/// it counts as a turn past that end.
public enum ReaderEdge: Hashable, Sendable {
    /// Before the first page.
    case start
    /// After the last page.
    case end
}

/// What an app gives one end of a publication with
/// `readerEdgePages(start:end:content:)`.
public enum ReaderEdgePage: Hashable, Sendable {
    /// No page: a turn past the end is only counted.
    case none
    /// A page that reading stops at, such as one saying there's no chapter
    /// after this one.
    case stop
    /// A page that reading goes on through, to whatever's past it, such as
    /// the next chapter.
    case through

    /// Whether a turn or pull on past this end counts as one past it.
    /// Without a page, every one does, for the app to act on; a stop is
    /// where reading ends.
    var countsTurnsPast: Bool {
        self != .stop
    }
}

/// Where a page view controller can be outside a publication's pages: on
/// an end's own page, or on the page past it, which opens what comes next.
enum OutsidePlace: Hashable {
    case edge(ReaderEdge)
    case past(ReaderEdge)

    var edge: ReaderEdge {
        switch self {
        case .edge(let edge), .past(let edge): edge
        }
    }

    /// The place a turn goes to from here, forward or back. `nil` when it
    /// leaves for the publication's pages, or when there's nothing further
    /// on: ``isInside(afterTurning:)`` tells which.
    func turned(forward: Bool) -> OutsidePlace? {
        switch (self, forward) {
        case (.edge(.end), true): .past(.end)
        case (.past(.end), false): .edge(.end)
        case (.edge(.start), false): .past(.start)
        case (.past(.start), true): .edge(.start)
        default: nil
        }
    }

    /// Whether a turn from here goes back among the publication's pages.
    func isInside(afterTurning forward: Bool) -> Bool {
        self == .edge(.end) && !forward || self == .edge(.start) && forward
    }
}
