import Foundation

/// Builds small PDFs in tests, so no binary fixtures are committed.
package enum PDFFixture {
    /// An outline entry: a title, the 1-based page it opens, and children.
    package struct Entry {
        package var title: String
        package var page: Int
        package var children: [Entry]

        package init(_ title: String, page: Int, children: [Entry] = []) {
            self.title = title
            self.page = page
            self.children = children
        }
    }

    /// A PDF with `pageCount` pages, an outline and document info. Pages are
    /// blank unless `text` gives them a line of ASCII text, by 1-based page.
    package static func document(
        pageCount: Int = 3,
        title: String? = "The Lighthouse",
        author: String? = "Ada Writer; Tom Two",
        outline: [Entry] = [
            Entry("Chapter One", page: 1),
            Entry("Chapter Two", page: 3, children: [Entry("Section", page: 3)]),
        ],
        text: [Int: String] = [:]
    ) -> Data {
        var objects: [String] = []
        func add(_ body: String) -> Int {
            objects.append(body)
            return objects.count
        }
        func reserve() -> Int {
            add("")
        }

        let catalog = reserve()
        let pages = reserve()
        let blank = add("<< /Length 0 >>\nstream\n\nendstream")
        let font = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
        let pageIDs = (0..<pageCount).map { index in
            var content = blank
            var resources = "<< >>"
            if let line = text[index + 1] {
                let escaped = line.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "(", with: "\\(")
                    .replacingOccurrences(of: ")", with: "\\)")
                let stream = "BT /F1 12 Tf 20 270 Td (\(escaped)) Tj ET"
                content = add("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream")
                resources = "<< /Font << /F1 \(font) 0 R >> >>"
            }
            return add("<< /Type /Page /Parent \(pages) 0 R /MediaBox [0 0 200 300] /Contents \(content) 0 R /Resources \(resources) >>")
        }
        objects[pages - 1] = "<< /Type /Pages /Kids [\(pageIDs.map { "\($0) 0 R" }.joined(separator: " "))] /Count \(pageCount) >>"

        var outlineRoot: Int?
        if !outline.isEmpty {
            let root = reserve()
            func write(_ entries: [Entry], parent: Int) -> (first: Int, last: Int) {
                let ids = entries.map { _ in reserve() }
                for (index, entry) in entries.enumerated() {
                    var body = "<< /Title (\(entry.title)) /Parent \(parent) 0 R /Dest [\(pageIDs[entry.page - 1]) 0 R /Fit]"
                    if index > 0 { body += " /Prev \(ids[index - 1]) 0 R" }
                    if index + 1 < ids.count { body += " /Next \(ids[index + 1]) 0 R" }
                    if !entry.children.isEmpty {
                        let children = write(entry.children, parent: ids[index])
                        body += " /First \(children.first) 0 R /Last \(children.last) 0 R /Count \(entry.children.count)"
                    }
                    objects[ids[index] - 1] = body + " >>"
                }
                return (ids[0], ids[ids.count - 1])
            }
            let top = write(outline, parent: root)
            objects[root - 1] = "<< /Type /Outlines /First \(top.first) 0 R /Last \(top.last) 0 R /Count \(outline.count) >>"
            outlineRoot = root
        }
        objects[catalog - 1] = "<< /Type /Catalog /Pages \(pages) 0 R" + (outlineRoot.map { " /Outlines \($0) 0 R" } ?? "") + " >>"

        var info: [String] = []
        if let title { info.append("/Title (\(title))") }
        if let author { info.append("/Author (\(author))") }
        let infoID = add("<< \(info.joined(separator: " ")) >>")

        var file = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(index + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            file += String(repeating: "0", count: 10 - String(offset).count) + "\(offset) 00000 n \n"
        }
        file += "trailer\n<< /Size \(objects.count + 1) /Root \(catalog) 0 R /Info \(infoID) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(file.utf8)
    }
}
