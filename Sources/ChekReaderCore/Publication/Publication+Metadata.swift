extension Publication {
    /// Bibliographic and presentation details about a publication.
    public struct Metadata: Hashable, Sendable {
        /// The publication's unique identifier, such as an ISBN or UUID URN.
        public var identifier: String?
        /// The main title. `nil` when the publication doesn't declare one.
        public var title: String?
        /// The title to sort by, when it differs from ``title``.
        public var sortTitle: String?
        /// The subtitle, if any.
        public var subtitle: String?
        /// The authors, in the order the publication lists them.
        public var authors: [Contributor]
        /// Everyone else credited, such as translators and illustrators.
        public var contributors: [Contributor]
        /// The publishers.
        public var publishers: [String]
        /// The languages of the content, as BCP 47 tags such as `en` or `pt-BR`.
        public var languages: [String]
        /// A description of the publication, which may contain HTML.
        public var summary: String?
        /// The publication date as written in the publication, usually ISO 8601.
        public var published: String?
        /// When the publication was last modified, usually ISO 8601.
        public var modified: String?
        /// Subjects and genres.
        public var subjects: [String]
        /// The series the publication belongs to, if any.
        public var series: Series?
        /// The direction pages advance in.
        public var readingProgression: ReadingProgression
        /// Whether content reflows or keeps a fixed page layout.
        public var layout: Layout
        /// Accessibility claims made by the publisher.
        public var accessibility: Accessibility

        public init(
            identifier: String? = nil,
            title: String? = nil,
            sortTitle: String? = nil,
            subtitle: String? = nil,
            authors: [Contributor] = [],
            contributors: [Contributor] = [],
            publishers: [String] = [],
            languages: [String] = [],
            summary: String? = nil,
            published: String? = nil,
            modified: String? = nil,
            subjects: [String] = [],
            series: Series? = nil,
            readingProgression: ReadingProgression = .auto,
            layout: Layout = .reflowable,
            accessibility: Accessibility = Accessibility()
        ) {
            self.identifier = identifier
            self.title = title
            self.sortTitle = sortTitle
            self.subtitle = subtitle
            self.authors = authors
            self.contributors = contributors
            self.publishers = publishers
            self.languages = languages
            self.summary = summary
            self.published = published
            self.modified = modified
            self.subjects = subjects
            self.series = series
            self.readingProgression = readingProgression
            self.layout = layout
            self.accessibility = accessibility
        }
    }

    /// A person or organization credited in a publication.
    public struct Contributor: Hashable, Sendable {
        /// The name as displayed.
        public var name: String
        /// The name to sort by, such as "Austen, Jane".
        public var sortAs: String?
        /// A MARC relator code such as `aut`, `trl` or `ill`, when known.
        public var role: String?

        public init(name: String, sortAs: String? = nil, role: String? = nil) {
            self.name = name
            self.sortAs = sortAs
            self.role = role
        }
    }

    /// A series and the publication's place in it.
    public struct Series: Hashable, Sendable {
        public var name: String
        /// The position in the series, which can be fractional, such as 2.5.
        public var position: Double?

        public init(name: String, position: Double? = nil) {
            self.name = name
            self.position = position
        }
    }

    /// The direction pages advance in.
    public enum ReadingProgression: String, Hashable, Sendable {
        /// Pages advance left to right.
        case leftToRight = "ltr"
        /// Pages advance right to left, as in Japanese manga.
        case rightToLeft = "rtl"
        /// The publication doesn't say. Follow the content's language.
        case auto
    }

    /// Whether content reflows or keeps a fixed page layout.
    public enum Layout: String, Hashable, Sendable {
        case reflowable
        /// Each page has a fixed size, as in EPUB `pre-paginated`.
        case fixed
    }

    /// Accessibility claims made by the publisher, using schema.org and
    /// EPUB Accessibility vocabulary.
    public struct Accessibility: Hashable, Sendable {
        /// Standards the publication claims to meet, such as
        /// `EPUB Accessibility 1.1 - WCAG 2.1 Level AA`.
        public var conformsTo: [String]
        /// How the content can be perceived, such as `textual` or `visual`.
        public var accessModes: [String]
        /// Combinations of modes that are enough to read the whole
        /// publication, such as `textual` or `textual,visual`.
        public var accessModesSufficient: [String]
        /// Features such as `structuralNavigation` or `alternativeText`.
        public var features: [String]
        /// Hazards such as `flashing`, or `none`.
        public var hazards: [String]
        /// A human-readable summary of the publication's accessibility.
        public var summary: String?

        public init(
            conformsTo: [String] = [],
            accessModes: [String] = [],
            accessModesSufficient: [String] = [],
            features: [String] = [],
            hazards: [String] = [],
            summary: String? = nil
        ) {
            self.conformsTo = conformsTo
            self.accessModes = accessModes
            self.accessModesSufficient = accessModesSufficient
            self.features = features
            self.hazards = hazards
            self.summary = summary
        }

        /// Whether the publisher made any accessibility claim.
        public var isEmpty: Bool {
            conformsTo.isEmpty && accessModes.isEmpty && accessModesSufficient.isEmpty
                && features.isEmpty && hazards.isEmpty && summary == nil
        }
    }
}
