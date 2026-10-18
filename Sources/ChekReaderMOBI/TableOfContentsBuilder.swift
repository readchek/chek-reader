import ChekReaderCore

/// Nests a flat list of table of contents entries by their depth.
///
/// MOBI NCX indexes list entries in reading order with a heading level, and
/// optionally parent and child links. The depths alone are enough to nest
/// them and can't form cycles, so a damaged parent link can't loop.
enum TableOfContentsBuilder {
    struct Entry: Sendable {
        let title: String
        let href: String
        let depth: Int
    }

    /// Deeper entries than this are attached at this depth, so a hostile
    /// file can't nest without bound.
    static let maxDepth = 32

    static func links(_ entries: [Entry], mediaType: String) -> [Link] {
        // Builds a tree of indices first, since Link is a value type and
        // can't be appended to once nested.
        var children: [[Int]] = Array(repeating: [], count: entries.count)
        var roots: [Int] = []
        // The open ancestors: entry index and depth.
        var stack: [(index: Int, depth: Int)] = []
        for (index, entry) in entries.enumerated() {
            let depth = min(max(entry.depth, 0), maxDepth)
            while let last = stack.last, last.depth >= depth {
                stack.removeLast()
            }
            if let parent = stack.last {
                children[parent.index].append(index)
            } else {
                roots.append(index)
            }
            stack.append((index: index, depth: depth))
        }
        func link(_ index: Int) -> Link {
            Link(
                href: entries[index].href,
                mediaType: mediaType,
                title: entries[index].title,
                children: children[index].map(link)
            )
        }
        return roots.map(link)
    }
}
