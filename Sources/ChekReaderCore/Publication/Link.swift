/// A resource in a publication, such as a chapter, a stylesheet or a
/// table of contents entry.
///
/// Hrefs are paths from the publication's root, such as
/// `OEBPS/Text/chapter1.xhtml`, already percent-decoded. A table of contents
/// entry may add a fragment, as in `OEBPS/Text/chapter1.xhtml#section2`.
public struct Link: Hashable, Sendable {
    /// The resource's path from the publication's root, with an optional fragment.
    public var href: String
    /// The resource's media type, such as `application/xhtml+xml`.
    public var mediaType: String?
    /// The title shown for the link, such as a chapter name.
    public var title: String?
    /// What the link is for, such as `cover` or `contents`. Landmarks use
    /// their EPUB structural semantics, such as `bodymatter`.
    public var rels: Set<String>
    /// Details about how to present or read the resource.
    public var properties: Properties
    /// Nested entries, for tables of contents.
    public var children: [Link]

    public init(
        href: String,
        mediaType: String? = nil,
        title: String? = nil,
        rels: Set<String> = [],
        properties: Properties = Properties(),
        children: [Link] = []
    ) {
        self.href = href
        self.mediaType = mediaType
        self.title = title
        self.rels = rels
        self.properties = properties
        self.children = children
    }

    /// The href without its fragment, which is the path of the resource itself.
    public var path: String {
        guard let hash = href.firstIndex(of: "#") else { return href }
        return String(href[..<hash])
    }

    /// Details about how to present or read a resource.
    public struct Properties: Hashable, Sendable {
        /// Which side of a two-page spread the resource goes on, in a fixed-layout publication.
        public var page: Page?
        /// A layout that overrides the publication's ``Publication/Metadata/layout`` for this resource.
        public var layout: Publication.Layout?
        /// What the resource contains, from its EPUB manifest properties,
        /// such as `scripted`, `mathml`, `svg` or `remote-resources`.
        public var contains: Set<String>
        /// The font obfuscation the resource was stored with, if any.
        /// ``Publication/data(at:)`` returns the font already de-obfuscated.
        public var obfuscation: FontObfuscation?

        public init(
            page: Page? = nil,
            layout: Publication.Layout? = nil,
            contains: Set<String> = [],
            obfuscation: FontObfuscation? = nil
        ) {
            self.page = page
            self.layout = layout
            self.contains = contains
            self.obfuscation = obfuscation
        }
    }

    /// A side of a two-page spread.
    public enum Page: String, Hashable, Sendable {
        case left
        case right
        case center
    }

    /// A font obfuscation scheme. These hide embedded fonts from casual
    /// copying and are not DRM, so publications that use them still open.
    public enum FontObfuscation: String, Hashable, Sendable {
        /// The IDPF algorithm, `http://www.idpf.org/2008/embedding`.
        case idpf = "http://www.idpf.org/2008/embedding"
        /// The Adobe algorithm, `http://ns.adobe.com/pdf/enc#RC`.
        case adobe = "http://ns.adobe.com/pdf/enc#RC"
    }
}
