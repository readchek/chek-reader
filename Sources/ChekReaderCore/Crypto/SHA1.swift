import Foundation

/// SHA-1, used only to derive the key for IDPF font obfuscation.
///
/// SHA-1 is broken for security purposes, but the EPUB specification fixes
/// it for this one non-security use. CryptoKit isn't available on Linux,
/// and core products take no dependencies, so it's implemented here.
package enum SHA1 {
    /// The 20-byte digest of `data`.
    package static func digest(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var h: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0)
        var words = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let base = chunk + index * 4
                var word: UInt32 = 0
                for offset in 0..<4 {
                    word = word << 8 | UInt32(message[base + offset])
                }
                words[index] = word
            }
            for index in 16..<80 {
                words[index] = rotate(words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16], by: 1)
            }
            var (a, b, c, d, e) = h
            for index in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch index {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A82_7999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9_EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1B_BCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62_C1D6
                }
                var temp: UInt32 = rotate(a, by: 5) &+ f
                temp = temp &+ e &+ k
                temp = temp &+ words[index]
                e = d
                d = c
                c = rotate(b, by: 30)
                b = a
                a = temp
            }
            h = (h.0 &+ a, h.1 &+ b, h.2 &+ c, h.3 &+ d, h.4 &+ e)
        }
        // Spelled out step by step: the one-expression form is too slow for
        // the type checker.
        var digest: [UInt8] = []
        digest.reserveCapacity(20)
        for word in [h.0, h.1, h.2, h.3, h.4] {
            for shift in stride(from: UInt32(24), through: 0, by: -8) {
                digest.append(UInt8(truncatingIfNeeded: word >> shift))
            }
        }
        return digest
    }

    private static func rotate(_ value: UInt32, by amount: UInt32) -> UInt32 {
        value << amount | value >> (32 - amount)
    }
}
