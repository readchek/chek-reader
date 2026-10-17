/// Fixed positions through a publication, like page numbers that don't
/// change with the screen or text size.
///
/// Each reflowable resource gets one position per 1,024 bytes, and each
/// fixed-layout resource gets one, as Readium does, so positions match
/// between apps built on either.
///
/// ```swift
/// let positions = try await publication.positions()
/// print("Position \(positions.locate(location).locations.position ?? 1) of \(positions.count)")
/// ```
public struct PositionList: Hashable, Sendable {
    /// The bytes of reflowable text that make one position.
    public static let bytesPerPosition: Int64 = 1024

    /// Every position, in order. Each one's ``Locator/Locations/position``
    /// is its 1-based index here.
    public let locators: [Locator]
    /// The index in ``locators`` of each reading order resource's first position.
    private let starts: [Int]

    /// Builds the list from how many positions each reading order resource has.
    package init(readingOrder: [Locator], counts: [Int]) {
        precondition(readingOrder.count == counts.count)
        let total = counts.reduce(0) { $0 + max(1, $1) }
        var locators: [Locator] = []
        locators.reserveCapacity(total)
        var starts: [Int] = []
        for (resource, count) in zip(readingOrder, counts) {
            starts.append(locators.count)
            let count = max(1, count)
            for index in 0..<count {
                var locator = resource
                locator.locations.fragments = []
                locator.locations.progression = Double(index) / Double(count)
                locator.locations.position = locators.count + 1
                locator.locations.totalProgression = Double(locators.count) / Double(total)
                locator.text = nil
                locators.append(locator)
            }
        }
        self.locators = locators
        self.starts = starts
    }

    /// The number of positions.
    public var count: Int { locators.count }

    /// The locator for a 1-based position, or `nil` when it's out of range.
    public func locator(at position: Int) -> Locator? {
        locators.indices.contains(position - 1) ? locators[position - 1] : nil
    }

    /// The position at a point through the whole publication, from 0 to 1.
    public func locator(atTotalProgression progression: Double) -> Locator? {
        guard !locators.isEmpty, progression.isFinite else { return nil }
        let index = Int((min(max(progression, 0), 1) * Double(locators.count)).rounded(.down))
        return locators[min(index, locators.count - 1)]
    }

    /// `locator` with its ``Locator/Locations/position`` and
    /// ``Locator/Locations/totalProgression`` filled in, from the resource
    /// it's in and its progression through that resource.
    ///
    /// - Parameter resource: The reading order index of the locator's resource.
    public func locate(_ locator: Locator, inResource resource: Int) -> Locator {
        guard starts.indices.contains(resource) else { return locator }
        let start = starts[resource]
        let end = resource + 1 < starts.count ? starts[resource + 1] : locators.count
        let count = end - start
        let progression = min(max(locator.locations.progression ?? 0, 0), 1)
        let offset = min(Int((progression * Double(count)).rounded(.down)), count - 1)
        var located = locator
        located.locations.position = start + offset + 1
        // Within the resource, the total moves smoothly rather than in steps.
        located.locations.totalProgression = (Double(start) + progression * Double(count)) / Double(locators.count)
        return located
    }
}

extension Publication {
    /// Works out the publication's ``PositionList``.
    ///
    /// Sizes usually come from the archive's directory. Resources from a
    /// ``ResourceProvider`` are read to measure them, so call this off the
    /// critical path and keep the result.
    public func positions() async throws(ReaderError) -> PositionList {
        var resources: [Locator] = []
        var counts: [Int] = []
        for link in readingOrder {
            try ReaderError.checkCancellation()
            // Every resource gets an entry, so indices match the reading order.
            let locator = locator(for: Link(href: link.path))
                ?? Locator(href: link.path, mediaType: link.mediaType ?? MediaType.forPath(link.path))
            let fixed = (link.properties.layout ?? metadata.layout) == .fixed
            var count = 1
            if !fixed {
                let length = try await length(of: link.path)
                count = Int(min(max(1, (length + PositionList.bytesPerPosition - 1) / PositionList.bytesPerPosition), 1 << 24))
            }
            resources.append(locator)
            counts.append(count)
        }
        return PositionList(readingOrder: resources, counts: counts)
    }
}
