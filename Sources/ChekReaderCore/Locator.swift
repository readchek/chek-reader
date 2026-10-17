/// A position in a publication.
///
/// The JSON form matches the Readium Locator model, so positions can be
/// exchanged with other Readium-compatible apps and servers. Restoring tries
/// the most precise information first: the fragment anchor, then the text
/// context, then the progression within the resource, then the progression
/// within the whole publication.
public struct Locator: Hashable, Sendable, Codable {
    /// The resource the position is in, relative to the publication.
    public var href: String
    /// The resource's media type.
    public var mediaType: String
    /// The title of the section, when known.
    public var title: String?
    public var locations: Locations
    public var text: Text?

    public init(
        href: String,
        mediaType: String,
        title: String? = nil,
        locations: Locations = Locations(),
        text: Text? = nil
    ) {
        self.href = href
        self.mediaType = mediaType
        self.title = title
        self.locations = locations
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case href
        case mediaType = "type"
        case title
        case locations
        case text
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        href = try container.decode(String.self, forKey: .href)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        locations = try container.decodeIfPresent(Locations.self, forKey: .locations) ?? Locations()
        text = try container.decodeIfPresent(Text.self, forKey: .text)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(href, forKey: .href)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(title, forKey: .title)
        if locations != Locations() {
            try container.encode(locations, forKey: .locations)
        }
        try container.encodeIfPresent(text, forKey: .text)
    }

    /// Where in the resource and publication the position is.
    public struct Locations: Hashable, Sendable, Codable {
        /// Fragment identifiers such as an element ID or `page=12`.
        public var fragments: [String]
        /// Progress within the resource, from 0 to 1.
        public var progression: Double?
        /// Progress within the whole publication, from 0 to 1.
        public var totalProgression: Double?
        /// A 1-based position in the publication's position list.
        public var position: Int?

        public init(
            fragments: [String] = [],
            progression: Double? = nil,
            totalProgression: Double? = nil,
            position: Int? = nil
        ) {
            self.fragments = fragments
            self.progression = progression
            self.totalProgression = totalProgression
            self.position = position
        }

        private enum CodingKeys: String, CodingKey {
            case fragments, progression, totalProgression, position
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fragments = try container.decodeIfPresent([String].self, forKey: .fragments) ?? []
            progression = try container.decodeIfPresent(Double.self, forKey: .progression)
            totalProgression = try container.decodeIfPresent(Double.self, forKey: .totalProgression)
            position = try container.decodeIfPresent(Int.self, forKey: .position)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if !fragments.isEmpty {
                try container.encode(fragments, forKey: .fragments)
            }
            try container.encodeIfPresent(progression, forKey: .progression)
            try container.encodeIfPresent(totalProgression, forKey: .totalProgression)
            try container.encodeIfPresent(position, forKey: .position)
        }
    }

    /// Text around the position, used to find it again when the anchor no
    /// longer matches, for example after the publication is updated.
    public struct Text: Hashable, Sendable, Codable {
        public var before: String?
        public var highlight: String?
        public var after: String?

        public init(before: String? = nil, highlight: String? = nil, after: String? = nil) {
            self.before = before
            self.highlight = highlight
            self.after = after
        }
    }
}
