import Foundation

/// Builds TAR archives in tests, so no binary fixtures are committed.
package struct TARFixture {
    private var archive = Data()

    package init() {}

    /// Adds a regular file. Names longer than 100 bytes get a GNU long name entry.
    package mutating func add(_ name: String, _ content: Data, checksum: Int? = nil) {
        if name.utf8.count > 100 {
            append(name: "././@LongLink", type: "L", content: Data(name.utf8) + Data([0]))
        }
        append(name: String(name.prefix(100)), type: "0", content: content, checksum: checksum)
    }

    package mutating func add(_ name: String, _ content: String) {
        add(name, Data(content.utf8))
    }

    /// The archive, ended with two empty blocks.
    package func data() -> Data {
        archive + Data(count: 1024)
    }

    private mutating func append(name: String, type: Character, content: Data, checksum: Int? = nil) {
        var header = Data(count: 512)
        func put(_ text: String, at offset: Int) {
            for (index, byte) in text.utf8.enumerated() {
                header[offset + index] = byte
            }
        }
        put(name, at: 0)
        put("0000644\0", at: 100)
        put("0000000\0", at: 108)
        put("0000000\0", at: 116)
        put(String(format: "%011o", content.count), at: 124)
        put("00000000000\0", at: 136)
        put(String(type), at: 156)
        put("ustar\0", at: 257)
        put("00", at: 263)
        put("        ", at: 148)
        let sum = checksum ?? header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o", sum), at: 148)
        header[154] = 0
        archive.append(header)
        archive.append(content)
        let padding = (512 - content.count % 512) % 512
        archive.append(Data(count: padding))
    }
}
