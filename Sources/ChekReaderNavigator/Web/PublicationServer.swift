public import ChekReaderCore
public import Foundation

/// Serves a publication's resources to the web view under a private URL
/// scheme, so content never touches the network or the file system.
///
/// Every HTML document is served with a strict Content Security Policy:
/// resources load only from the publication, network requests are blocked,
/// and publication scripts run only when the app allows them.
public struct PublicationServer: Sendable {
    /// The URL scheme resources are served under.
    public static let scheme = "chek-reader"
    static let host = "publication"

    public let publication: Publication
    /// Whether the publication's own scripts may run.
    public let allowsScripts: Bool

    public init(publication: Publication, allowsScripts: Bool = false) {
        self.publication = publication
        self.allowsScripts = allowsScripts
    }

    /// The URL a resource is served at.
    public static func url(for href: String) -> URL {
        let link = Link(href: href)
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + link.path
        if let hash = href.firstIndex(of: "#") {
            components.fragment = String(href[href.index(after: hash)...])
        }
        // A path is always valid here, so building the URL can't fail.
        return components.url!
    }

    /// The href of a URL this server issued, with its fragment, or `nil`
    /// for any other URL.
    public static func href(for url: URL) -> String? {
        guard url.scheme == scheme, url.host() == host else { return nil }
        let path = String(url.path(percentEncoded: false).dropFirst())
        guard !path.isEmpty else { return nil }
        if let fragment = url.fragment(percentEncoded: false), !fragment.isEmpty {
            return path + "#" + fragment
        }
        return path
    }

    /// The policy sent with every HTML document.
    public var contentSecurityPolicy: String {
        let origin = "\(Self.scheme):"
        let scripts = allowsScripts ? "\(origin) 'unsafe-inline'" : "'none'"
        return [
            "default-src \(origin)",
            "script-src \(scripts)",
            "style-src \(origin) 'unsafe-inline'",
            "img-src \(origin) data:",
            "font-src \(origin) data:",
            "media-src \(origin)",
            "connect-src 'none'",
            "object-src 'none'",
            "form-action 'none'",
            "base-uri \(origin)",
        ].joined(separator: "; ")
    }

    /// A served resource.
    public struct Response: Sendable, Equatable {
        /// The HTTP status: 200, or 404 for anything the publication doesn't have.
        public var statusCode: Int
        /// HTTP headers, including the media type and, for documents, the policy.
        public var headers: [String: String]
        /// The resource's bytes.
        public var body: Data
    }

    /// The response for a request to `url`.
    public func response(for url: URL) async -> Response {
        guard let href = Self.href(for: url) else {
            return Self.failure(404)
        }
        let path = Link(href: href).path
        let data: Data
        do {
            data = try await publication.data(at: path)
        } catch .cancelled {
            return Self.failure(499)
        } catch {
            return Self.failure(404)
        }

        let mediaType = publication.link(for: path)?.mediaType ?? MediaType.forPath(path)
        var headers = [
            "Content-Type": mediaType,
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        ]
        var body = data
        if MediaType.isHTML(mediaType) {
            headers["Content-Security-Policy"] = contentSecurityPolicy
            body = Self.insertingPolicy(contentSecurityPolicy, into: data)
        }
        headers["Content-Length"] = String(body.count)
        return Response(statusCode: 200, headers: headers, body: body)
    }

    private static func failure(_ statusCode: Int) -> Response {
        Response(statusCode: statusCode, headers: ["Content-Length": "0"], body: Data())
    }

    /// Adds the policy as a `meta` element at the start of `head` too, so it
    /// applies even where a web view ignores headers on custom schemes.
    static func insertingPolicy(_ policy: String, into document: Data) -> Data {
        guard let headStart = document.range(of: Data("<head".utf8)) ?? document.range(of: Data("<HEAD".utf8)),
              let tagEnd = document[headStart.upperBound...].firstIndex(of: UInt8(ascii: ">"))
        else { return document }
        let meta = #"<meta http-equiv="Content-Security-Policy" content="\#(policy)"/>"#
        var result = Data(document[..<document.index(after: tagEnd)])
        result.append(Data(meta.utf8))
        result.append(document[document.index(after: tagEnd)...])
        return result
    }
}
