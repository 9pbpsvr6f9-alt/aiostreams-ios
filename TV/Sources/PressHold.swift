import SwiftUI
import UIKit

/// Tells when the remote's left or right is held down, and when it's let go, which SwiftUI's move
/// commands can't: they report a press once. Long-press recognizers on the window see the presses
/// that reach whatever has focus. `begin` returns whether to take this hold.
struct PressHold: UIViewRepresentable {
    var begin: (_ direction: Int) -> Bool
    var end: () -> Void

    func makeUIView(context: Context) -> Catcher {
        let view = Catcher()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Catcher, context: Context) {
        view.begin = begin
        view.end = end
    }

    final class Catcher: UIView {
        var begin: (Int) -> Bool = { _ in false }
        var end: () -> Void = {}
        private var recognizers: [UILongPressGestureRecognizer: Int] = [:]
        private var holding = false

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            for recognizer in recognizers.keys { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizers.removeAll()
            guard let newWindow else { return }
            for (press, direction) in [(UIPress.PressType.leftArrow, -1), (UIPress.PressType.rightArrow, 1)] {
                let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
                recognizer.allowedPressTypes = [NSNumber(value: press.rawValue)]
                recognizer.allowedTouchTypes = []
                recognizer.minimumPressDuration = 0.45
                // A click still reaches the page, which skips 10 seconds.
                recognizer.cancelsTouchesInView = false
                newWindow.addGestureRecognizer(recognizer)
                recognizers[recognizer] = direction
            }
        }

        @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                holding = begin(recognizers[recognizer] ?? 1)
            case .ended, .cancelled, .failed:
                if holding { end() }
                holding = false
            default:
                break
            }
        }
    }
}
