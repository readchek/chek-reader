/// Languages for the MOBI header's locale field, a Windows language ID.
///
/// Only the primary language, the low byte, is mapped: books with an EXTH
/// language record use that instead, and the region rarely matters for
/// reading.
enum MOBILanguage {
    static func tag(forLocale locale: UInt32) -> String? {
        guard locale != MOBIHeader.null else { return nil }
        return primaryLanguages[UInt8(truncatingIfNeeded: locale)]
    }

    private static let primaryLanguages: [UInt8: String] = [
        0x01: "ar", 0x02: "bg", 0x03: "ca", 0x04: "zh", 0x05: "cs", 0x06: "da", 0x07: "de", 0x08: "el",
        0x09: "en", 0x0A: "es", 0x0B: "fi", 0x0C: "fr", 0x0D: "he", 0x0E: "hu", 0x0F: "is", 0x10: "it",
        0x11: "ja", 0x12: "ko", 0x13: "nl", 0x14: "no", 0x15: "pl", 0x16: "pt", 0x17: "rm", 0x18: "ro",
        0x19: "ru", 0x1A: "hr", 0x1B: "sk", 0x1C: "sq", 0x1D: "sv", 0x1E: "th", 0x1F: "tr", 0x20: "ur",
        0x21: "id", 0x22: "uk", 0x23: "be", 0x24: "sl", 0x25: "et", 0x26: "lv", 0x27: "lt", 0x29: "fa",
        0x2A: "vi", 0x2B: "hy", 0x2C: "az", 0x2D: "eu", 0x2F: "mk", 0x36: "af", 0x37: "ka", 0x38: "fo",
        0x39: "hi", 0x3E: "ms", 0x3F: "kk", 0x41: "sw", 0x43: "uz", 0x44: "tt", 0x45: "bn", 0x46: "pa",
        0x47: "gu", 0x48: "or", 0x49: "ta", 0x4A: "te", 0x4B: "kn", 0x4C: "ml", 0x4D: "as", 0x4E: "mr",
        0x4F: "sa", 0x57: "kok",
    ]
}
