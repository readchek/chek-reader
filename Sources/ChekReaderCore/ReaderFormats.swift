import Synchronization

/// A format product's entry point, registered with ``ReaderFormats``.
public protocol ReaderFormatModule: Sendable {
    /// The formats this module opens.
    static var formats: [ReaderFormat] { get }

    /// Parses a publication in one of ``formats``.
    ///
    /// Apps call ``Publication/open(_:limits:)`` rather than this, so the
    /// format is detected and the right module chosen.
    static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication

    /// Finds `query` in a publication this module opened, for formats whose
    /// text the core can't read from markup, such as PDF.
    ///
    /// Apps call ``Publication/search(for:options:)`` rather than this.
    /// Returning `nil` has the core search the publication's HTML resources.
    static func search(_ publication: Publication, for query: String, options: SearchOptions) async throws(ReaderError) -> [Locator]?
}

extension ReaderFormatModule {
    /// Reports that the module doesn't open publications yet. Format
    /// engines replace this as they land.
    public static func open(_ source: PublicationSource, format: ReaderFormat, limits: ReaderLimits) async throws(ReaderError) -> Publication {
        throw .notYetImplemented(format)
    }

    /// Leaves searching to the core, which reads the publication's HTML.
    public static func search(_ publication: Publication, for query: String, options: SearchOptions) async throws(ReaderError) -> [Locator]? {
        nil
    }
}

/// The formats this app can open.
///
/// Each format product exposes a module type. Linking a product does not
/// register it: an app registers the modules it wants, once, at launch.
///
/// ```swift
/// ReaderFormats.register(EPUBModule.self, PDFModule.self)
/// ```
///
/// The `ChekReader` umbrella product registers its whole default set with
/// `ReaderFormats.registerDefaults()`.
public enum ReaderFormats {
    private static let registry = Mutex<[String: any ReaderFormatModule.Type]>([:])

    /// Registers modules. Registering a module again has no effect.
    public static func register(_ modules: any ReaderFormatModule.Type...) {
        registry.withLock { registry in
            for module in modules {
                for format in module.formats {
                    registry[format.id] = module
                }
            }
        }
    }

    /// The registered formats.
    public static var registered: Set<ReaderFormat> {
        let ids = registry.withLock { Set($0.keys) }
        return Set(ReaderFormat.all.filter { ids.contains($0.id) })
    }

    /// Whether `format` can be opened.
    public static func isRegistered(_ format: ReaderFormat) -> Bool {
        registry.withLock { $0[format.id] != nil }
    }

    /// The module for `format`, or ``ReaderError/formatNotIncluded(_:)``
    /// naming the product to add.
    public static func module(for format: ReaderFormat) throws(ReaderError) -> any ReaderFormatModule.Type {
        guard let module = registry.withLock({ $0[format.id] }) else {
            throw .formatNotIncluded(format)
        }
        return module
    }
}
