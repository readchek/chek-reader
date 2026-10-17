import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Parses XML into ``XMLNode`` trees, safely.
///
/// External entities and DTDs are never loaded, entity declarations are
/// rejected so entity expansion can't be used to exhaust memory, and nesting
/// deeper than ``ReaderLimits/maxXMLDepth`` fails with
/// ``ReaderError/limitExceeded(_:)``.
package enum XMLTree {
    /// Parses `data` and returns its root element.
    package static func parse(_ data: Data, limits: ReaderLimits) throws(ReaderError) -> XMLNode {
        // Publications have no use for their own entities, and declaring
        // them is how "billion laughs" documents expand without bound.
        if data.range(of: Data("<!ENTITY".utf8)) != nil {
            throw .malformed(reason: "An XML document declares entities, which aren't allowed in publications.")
        }

        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        #if canImport(Darwin)
        parser.externalEntityResolvingPolicy = .never
        #endif
        let builder = TreeBuilder(maxDepth: limits.maxXMLDepth)
        parser.delegate = builder
        let succeeded = parser.parse()

        if builder.exceededDepth {
            throw .limitExceeded(.xmlDepth)
        }
        guard succeeded, let root = builder.root else {
            let detail = parser.parserError.map { " (\($0.localizedDescription))" } ?? ""
            throw .malformed(reason: "An XML document isn't well-formed\(detail), line \(parser.lineNumber).")
        }
        return root
    }
}

/// Builds the tree from parser callbacks. Used by one parser on one thread.
private final class TreeBuilder: NSObject, XMLParserDelegate {
    private let maxDepth: Int
    private var stack: [XMLNode] = []
    private(set) var root: XMLNode?
    private(set) var exceededDepth = false

    init(maxDepth: Int) {
        self.maxDepth = maxDepth
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard stack.count < maxDepth else {
            exceededDepth = true
            parser.abortParsing()
            return
        }
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let namespace = namespaceURI.flatMap { $0.isEmpty ? nil : $0 }
        stack.append(XMLNode(name: name, namespace: namespace, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let element = stack.popLast() else { return }
        if stack.isEmpty {
            root = element
        } else {
            stack[stack.count - 1].children.append(.element(element))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendText(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        appendText(String(decoding: CDATABlock, as: UTF8.self))
    }

    private func appendText(_ text: String) {
        guard !stack.isEmpty else { return }
        let last = stack.count - 1
        if case .text(let previous) = stack[last].children.last {
            // The parser can split one run of text into several callbacks.
            stack[last].children[stack[last].children.count - 1] = .text(previous + text)
        } else {
            stack[last].children.append(.text(text))
        }
    }
}
