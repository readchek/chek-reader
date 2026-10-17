import ChekReaderCore
import Foundation

/// Reverses EPUB font obfuscation, so fonts can be handed to the renderer.
///
/// Both schemes XOR the start of the font with a key derived from the
/// publication's unique identifier. They hide fonts from casual copying and
/// are not DRM.
enum FontDeobfuscator {
    /// De-obfuscates `data` with `scheme`, keyed by the publication's
    /// `identifier`. Returns `nil` when the identifier can't produce a key.
    static func deobfuscate(_ data: Data, scheme: Link.FontObfuscation, identifier: String) -> Data? {
        let key: [UInt8]
        let length: Int
        switch scheme {
        case .idpf:
            // The identifier with all XML whitespace removed, hashed with SHA-1.
            let stripped = identifier.filter { !" \t\r\n".contains($0) }
            key = SHA1.digest(Data(stripped.utf8))
            length = 1040
        case .adobe:
            // The 16 bytes of the identifier's UUID.
            guard let uuid = adobeKey(identifier) else { return nil }
            key = uuid
            length = 1024
        }
        var bytes = [UInt8](data)
        for index in 0..<min(length, bytes.count) {
            bytes[index] ^= key[index % key.count]
        }
        return Data(bytes)
    }

    private static func adobeKey(_ identifier: String) -> [UInt8]? {
        var hex = identifier.lowercased()
        if hex.hasPrefix("urn:uuid:") {
            hex.removeFirst("urn:uuid:".count)
        }
        hex.removeAll { $0 == "-" }
        guard hex.count == 32 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

/// Serves an EPUB's resources with obfuscated fonts already reversed.
struct DeobfuscatingContainer: PublicationContainer {
    let base: any PublicationContainer
    let fonts: [String: Link.FontObfuscation]
    let identifier: String

    var paths: Set<String>? { base.paths }

    func length(of path: String) async -> Int64? {
        await base.length(of: path)
    }

    func data(at path: String) async throws(ReaderError) -> Data {
        let data = try await base.data(at: path)
        guard let scheme = fonts[path] else { return data }
        guard let font = FontDeobfuscator.deobfuscate(data, scheme: scheme, identifier: identifier) else {
            throw .malformed(reason: "The font \(path) is obfuscated, but the publication's identifier can't produce its key.")
        }
        return font
    }
}
