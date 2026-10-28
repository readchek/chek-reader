#if os(iOS)
import UIKit

/// Notices a swipe toward the next page on the last one. A page view
/// controller with no page to turn to lets the swipe go without a word,
/// and apps want to hear of it to go on to what comes next.
///
/// It watches alongside the page view controller's own gestures and never
/// stops them.
@MainActor
final class PastEndSwipe: NSObject, UIGestureRecognizerDelegate {
    private let isRightToLeft: Bool
    private let isAtEnd: () -> Bool
    private let didSwipe: () -> Void
    /// Whether the swipe began on the last page, since by its end a page
    /// may have turned.
    private var beganAtEnd = false

    init(in view: UIView, isRightToLeft: Bool, isAtEnd: @escaping () -> Bool, didSwipe: @escaping () -> Void) {
        self.isRightToLeft = isRightToLeft
        self.isAtEnd = isAtEnd
        self.didSwipe = didSwipe
        super.init()
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        view.addGestureRecognizer(recognizer)
    }

    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            beganAtEnd = isAtEnd()
        case .ended:
            guard beganAtEnd else { return }
            beganAtEnd = false
            let translation = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            // The next page comes in from the trailing side, so the finger
            // moves toward the leading one: left, or right in a
            // right-to-left publication.
            let distance = isRightToLeft ? translation.x : -translation.x
            let speed = isRightToLeft ? velocity.x : -velocity.x
            guard abs(translation.x) > abs(translation.y) * 1.5,
                  distance > 60 || (distance > 20 && speed > 500)
            else { return }
            didSwipe()
        case .cancelled, .failed:
            beganAtEnd = false
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif
