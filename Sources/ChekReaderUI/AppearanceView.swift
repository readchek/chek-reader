#if canImport(SwiftUI) && canImport(WebKit)
public import ChekReaderCore
public import ChekReaderNavigator
import Foundation
public import SwiftUI

/// Reading settings: text size and font, colors, and how pages turn.
/// Each change applies to the reader at once.
///
/// Text settings only show for reflowable publications, since fixed
/// pages, PDFs and comics keep their publisher's layout.
public struct AppearanceView: View {
    private let controller: ReaderController
    @State private var preferences: ReaderPreferences
    @Environment(\.dismiss) private var dismiss

    public init(controller: ReaderController) {
        self.controller = controller
        _preferences = State(wrappedValue: controller.preferences)
    }

    public var body: some View {
        NavigationStack {
            Form {
                if isReflowable {
                    textSection
                    Section {
                        Picker(selection: $preferences.theme) {
                            Text("Original", bundle: #bundle).tag(ReaderPreferences.Theme.original)
                            Text("Light", bundle: #bundle).tag(ReaderPreferences.Theme.light)
                            Text("Sepia", bundle: #bundle).tag(ReaderPreferences.Theme.sepia)
                            Text("Dark", bundle: #bundle).tag(ReaderPreferences.Theme.dark)
                        } label: {
                            Text("Theme", bundle: #bundle)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Colors", bundle: #bundle)
                    }
                }
                pagesSection
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Appearance", bundle: #bundle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", bundle: #bundle) }
                }
            }
        }
        .onChange(of: preferences) { _, preferences in
            Task { await controller.setPreferences(preferences) }
        }
    }

    private var textSection: some View {
        Section {
            HStack {
                Button {
                    preferences.fontScale -= 0.1
                } label: {
                    Label { Text("Smaller text", bundle: #bundle) } icon: { Text(verbatim: "A").font(.footnote) }
                }
                .disabled(preferences.fontScale <= ReaderPreferences.fontScaleRange.lowerBound)
                Slider(value: $preferences.fontScale, in: ReaderPreferences.fontScaleRange, step: 0.1) {
                    Text("Text size", bundle: #bundle)
                }
                .accessibilityValue(Text(verbatim: preferences.fontScale.formatted(.percent.precision(.fractionLength(0)))))
                Button {
                    preferences.fontScale += 0.1
                } label: {
                    Label { Text("Larger text", bundle: #bundle) } icon: { Text(verbatim: "A").font(.title2) }
                }
                .disabled(preferences.fontScale >= ReaderPreferences.fontScaleRange.upperBound)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            Picker(selection: $preferences.font) {
                Text("Original", bundle: #bundle).tag(ReaderPreferences.Font.original)
                Text("Serif", bundle: #bundle).tag(ReaderPreferences.Font.serif)
                Text("Sans Serif", bundle: #bundle).tag(ReaderPreferences.Font.sansSerif)
            } label: {
                Text("Font", bundle: #bundle)
            }
            Picker(selection: $preferences.lineHeight) {
                Text("Original", bundle: #bundle).tag(Double?.none)
                Text("Compact", bundle: #bundle).tag(Double?.some(1.2))
                Text("Normal", bundle: #bundle).tag(Double?.some(1.5))
                Text("Relaxed", bundle: #bundle).tag(Double?.some(1.8))
                Text("Loose", bundle: #bundle).tag(Double?.some(2.1))
            } label: {
                Text("Line Height", bundle: #bundle)
            }
            Picker(selection: $preferences.marginScale) {
                Text("None", bundle: #bundle).tag(0.0)
                Text("Narrow", bundle: #bundle).tag(0.5)
                Text("Normal", bundle: #bundle).tag(1.0)
                Text("Wide", bundle: #bundle).tag(2.0)
            } label: {
                Text("Margins", bundle: #bundle)
            }
        } header: {
            Text("Text", bundle: #bundle)
        }
    }

    private var pagesSection: some View {
        Section {
            Picker(selection: $preferences.pageTransition) {
                Text("Curl", bundle: #bundle).tag(ReaderPreferences.PageTransition.curl)
                Text("Slide", bundle: #bundle).tag(ReaderPreferences.PageTransition.slide)
            } label: {
                Text("Page Turn", bundle: #bundle)
            }
            if isComic {
                Picker(selection: $preferences.comicFlow) {
                    Text("Automatic", bundle: #bundle).tag(ReaderPreferences.ComicFlow.automatic)
                    Text("Page by Page", bundle: #bundle).tag(ReaderPreferences.ComicFlow.paged)
                    Text("Scrolling", bundle: #bundle).tag(ReaderPreferences.ComicFlow.scrolled)
                } label: {
                    Text("Comic Layout", bundle: #bundle)
                }
            }
            Picker(selection: $preferences.readingProgression) {
                Text("Original", bundle: #bundle).tag(Publication.ReadingProgression?.none)
                Text("Left to Right", bundle: #bundle).tag(Publication.ReadingProgression?.some(.leftToRight))
                Text("Right to Left", bundle: #bundle).tag(Publication.ReadingProgression?.some(.rightToLeft))
            } label: {
                Text("Reading Direction", bundle: #bundle)
            }
        } header: {
            Text("Pages", bundle: #bundle)
        } footer: {
            if isComic {
                Text("Manga reads right to left. Changing the direction opens the publication again at the same page.", bundle: #bundle)
            } else {
                Text("Changing the direction opens the publication again at the same place.", bundle: #bundle)
            }
        }
    }

    private var isReflowable: Bool {
        controller.publication?.metadata.layout == .reflowable
    }

    private var isComic: Bool {
        guard let publication = controller.publication else { return false }
        return [.cbz, .cbt, .cbr, .cb7].contains(publication.format)
    }
}
#endif
