import ChekReaderCore

/// Reads `META-INF/encryption.xml`, telling DRM apart from font obfuscation.
enum EPUBEncryption {
    static let path = "META-INF/encryption.xml"

    /// The obfuscated fonts by path.
    ///
    /// - Throws: ``ReaderError/drmProtected(scheme:)`` when any resource is
    ///   encrypted with something other than font obfuscation.
    static func obfuscatedFonts(in root: XMLNode, paths: Set<String>?) throws(ReaderError) -> [String: Link.FontObfuscation] {
        var fonts: [String: Link.FontObfuscation] = [:]
        for data in root.descendants(named: "EncryptedData") {
            let algorithm = data.firstElement(named: "EncryptionMethod")?.attribute("Algorithm") ?? ""
            guard let obfuscation = Link.FontObfuscation(rawValue: algorithm) else {
                throw .drmProtected(scheme: scheme(paths: paths, algorithm: algorithm))
            }
            // Cipher references are relative to the container's root.
            guard let uri = data.firstDescendant(named: "CipherReference")?.attribute("URI"),
                  let path = EPUBHref.resolve(uri, from: "")
            else { continue }
            fonts[path] = obfuscation
        }
        return fonts
    }

    /// Names the DRM scheme from the files it leaves in META-INF.
    private static func scheme(paths: Set<String>?, algorithm: String) -> String {
        let paths = paths ?? []
        if paths.contains("META-INF/license.lcpl") {
            return "Readium LCP"
        }
        if paths.contains("META-INF/rights.xml") {
            return "Adobe DRM"
        }
        if paths.contains("META-INF/sinf.xml") {
            return "Apple FairPlay"
        }
        return algorithm.isEmpty ? "an unknown encryption scheme" : "encryption (\(algorithm))"
    }
}
