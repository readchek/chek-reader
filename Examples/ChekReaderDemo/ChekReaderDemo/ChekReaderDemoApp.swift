import ChekReader
import SwiftUI

@main
struct ChekReaderDemoApp: App {
    init() {
        ReaderFormats.registerDefaults()
    }

    var body: some Scene {
        DocumentGroup { document in
            BookScreen(document: document)
        } makeReadableDocument: { configuration, context in
            BookDocument()
        }
    }
}

struct BookScreen: View {
    let document: BookDocument

    var body: some View {
        if let contents = document.contents {
            ReaderView(source: .data(contents.data, fileName: contents.fileName))
                .ignoresSafeArea()
        } else {
            ProgressView()
        }
    }
}
