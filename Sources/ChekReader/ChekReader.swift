@_exported import ChekReaderCore
@_exported import ChekReaderEPUB
@_exported import ChekReaderPDF
@_exported import ChekReaderComics
@_exported import ChekReaderText
@_exported import ChekReaderMOBI
@_exported import ChekReaderFB2
@_exported import ChekReaderNavigator
@_exported import ChekReaderUI

extension ReaderFormats {
    /// The modules in the umbrella product.
    public static let defaultModules: [any ReaderFormatModule.Type] = [
        EPUBModule.self,
        PDFModule.self,
        ComicsModule.self,
        TextModule.self,
        MOBIModule.self,
        FB2Module.self,
    ]

    /// Registers every module in the umbrella product.
    public static func registerDefaults() {
        for module in defaultModules {
            register(module)
        }
    }
}
