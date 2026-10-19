#if canImport(ImageIO) && canImport(SwiftUI)
import SwiftUI

/// Owns one session's ``ImageNavigator`` and turns its pages with taps,
/// swipes and the keyboard.
struct ImageNavigatorView: View {
    let controller: ReaderController
    @State private var navigator: ImageNavigator?
    @Environment(\.displayScale) private var displayScale

    init(controller: ReaderController) {
        self.controller = controller
        self.navigator = nil
    }

    var body: some View {
        GeometryReader { geometry in
            content(in: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .space, .pageUp, .pageDown, .home, .end]) { press in
                guard let key = Self.key(press.key) else { return .ignored }
                navigator?.handle(.key(key))
                return .handled
            }
            .onChange(of: geometry.size) { _, size in
                navigator?.setViewport(width: size.width, height: size.height, scale: displayScale)
            }
            .task {
                guard navigator == nil, let publication = controller.publication else { return }
                let created = ImageNavigator(controller: controller, publication: publication)
                created.setViewport(width: geometry.size.width, height: geometry.size.height, scale: displayScale)
                navigator = created
                await created.start()
            }
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        #if os(iOS)
        if let navigator {
            // A different transition needs a new page view controller.
            ImagePagerView(navigator: navigator)
                .id(navigator.pageTransition)
                .ignoresSafeArea()
        }
        #else
        ZStack {
            if let image = navigator?.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            let third = size.width / 3
            let zone: PageCommand.Input.Zone = location.x < third ? .left : location.x > third * 2 ? .right : .center
            navigator?.handle(.tap(zone))
        }
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height) else { return }
                navigator?.handle(.swipe(towardLeft: width < 0))
            }
        )
        #endif
    }

    private static func key(_ key: KeyEquivalent) -> PageCommand.Input.Key? {
        switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .up
        case .downArrow: .down
        case .space, .pageDown: .next
        case .pageUp: .previous
        case .home: .home
        case .end: .end
        default: nil
        }
    }
}
#endif
