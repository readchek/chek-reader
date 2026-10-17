/// A publication format the reader knows about.
///
/// Knowing about a format is separate from being able to open it: each
/// format's code lives in its own product, and an app opens only the
/// formats whose products it links and registers with ``ReaderFormats``.
public struct ReaderFormat: Hashable, Sendable, CustomStringConvertible {
    /// A stable identifier, such as `"epub"`.
    public let id: String
    /// A name for people, such as `"EPUB"`.
    public let name: String
    /// IANA media types, the preferred one first.
    public let mediaTypes: [String]
    /// File name extensions without the dot, the preferred one first.
    public let fileExtensions: [String]
    /// The product that implements this format.
    public let product: String

    public init(
        id: String,
        name: String,
        mediaTypes: [String],
        fileExtensions: [String],
        product: String
    ) {
        self.id = id
        self.name = name
        self.mediaTypes = mediaTypes
        self.fileExtensions = fileExtensions
        self.product = product
    }

    public var description: String { name }

    public static func == (lhs: ReaderFormat, rhs: ReaderFormat) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ReaderFormat {
    public static let epub = ReaderFormat(
        id: "epub", name: "EPUB",
        mediaTypes: ["application/epub+zip"],
        fileExtensions: ["epub"],
        product: "ChekReaderEPUB"
    )
    public static let pdf = ReaderFormat(
        id: "pdf", name: "PDF",
        mediaTypes: ["application/pdf"],
        fileExtensions: ["pdf"],
        product: "ChekReaderPDF"
    )
    public static let cbz = ReaderFormat(
        id: "cbz", name: "Comic Book ZIP",
        mediaTypes: ["application/vnd.comicbook+zip"],
        fileExtensions: ["cbz"],
        product: "ChekReaderComics"
    )
    public static let cbt = ReaderFormat(
        id: "cbt", name: "Comic Book TAR",
        mediaTypes: ["application/x-cbt"],
        fileExtensions: ["cbt"],
        product: "ChekReaderComics"
    )
    public static let plainText = ReaderFormat(
        id: "txt", name: "Plain text",
        mediaTypes: ["text/plain"],
        fileExtensions: ["txt", "text"],
        product: "ChekReaderText"
    )
    public static let markdown = ReaderFormat(
        id: "markdown", name: "Markdown",
        mediaTypes: ["text/markdown"],
        fileExtensions: ["md", "markdown"],
        product: "ChekReaderText"
    )
    public static let mobi = ReaderFormat(
        id: "mobi", name: "MOBI",
        mediaTypes: ["application/x-mobipocket-ebook"],
        fileExtensions: ["mobi", "prc"],
        product: "ChekReaderMOBI"
    )
    public static let azw3 = ReaderFormat(
        id: "azw3", name: "AZW3",
        mediaTypes: ["application/vnd.amazon.ebook"],
        fileExtensions: ["azw3", "azw"],
        product: "ChekReaderMOBI"
    )
    public static let fb2 = ReaderFormat(
        id: "fb2", name: "FictionBook",
        mediaTypes: ["application/x-fictionbook+xml"],
        fileExtensions: ["fb2"],
        product: "ChekReaderFB2"
    )
    public static let fb2Zip = ReaderFormat(
        id: "fb2.zip", name: "Zipped FictionBook",
        mediaTypes: ["application/x-zip-compressed-fb2"],
        fileExtensions: ["fb2.zip", "fbz"],
        product: "ChekReaderFB2"
    )
    public static let cbr = ReaderFormat(
        id: "cbr", name: "Comic Book RAR",
        mediaTypes: ["application/vnd.comicbook-rar"],
        fileExtensions: ["cbr"],
        product: "ChekReaderArchives"
    )
    public static let cb7 = ReaderFormat(
        id: "cb7", name: "Comic Book 7z",
        mediaTypes: ["application/x-cb7"],
        fileExtensions: ["cb7"],
        product: "ChekReaderArchives"
    )

    /// Every format in the 1.0 coverage matrix.
    public static let all: [ReaderFormat] = [
        .epub, .pdf, .cbz, .cbt, .plainText, .markdown,
        .mobi, .azw3, .fb2, .fb2Zip, .cbr, .cb7,
    ]
}
