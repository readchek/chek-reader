/// An element of a parsed XML document. It isn't called `XMLNode` because
/// Foundation has a class with that name on macOS.
///
/// Names are matched without their namespace prefix, so `dc:title` is found
/// as `title`. Publications use prefixes inconsistently, and the element's
/// position in the document tells the formats apart well enough.
package struct MarkupNode: Hashable, Sendable {
    /// The element's name without its prefix.
    package var name: String
    /// The element's namespace URI, if it has one.
    package var namespace: String?
    /// Attributes by their qualified name, such as `opf:role`.
    package var attributes: [String: String]
    /// Child elements and text, in document order.
    package var children: [Child]

    package enum Child: Hashable, Sendable {
        case element(MarkupNode)
        case text(String)
    }

    package init(name: String, namespace: String? = nil, attributes: [String: String] = [:], children: [Child] = []) {
        self.name = name
        self.namespace = namespace
        self.attributes = attributes
        self.children = children
    }

    /// The child elements, in document order.
    package var elements: [MarkupNode] {
        children.compactMap {
            if case .element(let element) = $0 { element } else { nil }
        }
    }

    /// The child elements named `name`.
    package func elements(named name: String) -> [MarkupNode] {
        elements.filter { $0.name == name }
    }

    /// The first child element named `name`.
    package func firstElement(named name: String) -> MarkupNode? {
        for case .element(let element) in children where element.name == name {
            return element
        }
        return nil
    }

    /// Every element below this one named `name`, depth first.
    package func descendants(named name: String) -> [MarkupNode] {
        var found: [MarkupNode] = []
        collect(named: name, into: &found)
        return found
    }

    private func collect(named name: String, into found: inout [MarkupNode]) {
        for case .element(let element) in children {
            if element.name == name {
                found.append(element)
            }
            element.collect(named: name, into: &found)
        }
    }

    /// The first element below this one named `name`, depth first.
    package func firstDescendant(named name: String) -> MarkupNode? {
        for case .element(let element) in children {
            if element.name == name {
                return element
            }
            if let found = element.firstDescendant(named: name) {
                return found
            }
        }
        return nil
    }

    /// The value of the attribute with local name `name`, with or without a
    /// prefix. An unprefixed attribute wins over a prefixed one.
    package func attribute(_ name: String) -> String? {
        if let value = attributes[name] {
            return value
        }
        let suffix = ":" + name
        return attributes.first { $0.key.hasSuffix(suffix) }?.value
    }

    /// All the text inside the element, including its descendants'.
    package var text: String {
        var result = ""
        appendText(to: &result)
        return result
    }

    private func appendText(to result: inout String) {
        for child in children {
            switch child {
            case .text(let text): result += text
            case .element(let element): element.appendText(to: &result)
            }
        }
    }

    /// The text with runs of whitespace collapsed to single spaces and trimmed,
    /// or `nil` when there is none.
    package var trimmedText: String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
