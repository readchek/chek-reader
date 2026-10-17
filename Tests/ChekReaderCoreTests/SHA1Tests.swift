import ChekReaderCore
import Foundation
import Testing

@Suite struct SHA1Tests {
    @Test(arguments: [
        ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
        ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
        (String(repeating: "a", count: 1000), "291e9a6c66994949b57ba5e650361e98fc36b1ba"),
    ])
    func matchesReferenceDigests(input: String, expected: String) {
        let hex = SHA1.digest(Data(input.utf8)).map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(hex == expected)
    }
}
