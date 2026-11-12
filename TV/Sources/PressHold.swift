import SwiftUI
import UIKit

/// Tells when the remote's left or right is held down, and when it's let go, which SwiftUI's move
/// commands can't: they report a press once. A recognizer on the window watches the raw presses
/// that reach whatever has focus. It never claims them, so SwiftUI still sees every click, and it
/// runs alongside SwiftUI's own recognizers rather than waiting on them. `begin` returns whether
/// to take this hold.
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

    static func dismantleUIView(_ view: Catcher, coordinator: ()) {
        view.detach()
    }

    final class Catcher: UIView, UIGestureRecognizerDelegate {
        var begin: (Int) -> Bool = { _ in false }
        var end: () -> Void = {}
        private var watcher: Watcher?

        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            detach()
            guard let newWindow else { return }
            let watcher = Watcher()
            watcher.delegate = self
            watcher.began = { [weak self] direction in self?.begin(direction) ?? false }
            watcher.ended = { [weak self] in self?.end() }
            newWindow.addGestureRecognizer(watcher)
            self.watcher = watcher
        }

        func detach() {
            guard let watcher else { return }
            watcher.stop()
            watcher.view?.removeGestureRecognizer(watcher)
            self.watcher = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            press.type == .leftArrow || press.type == .rightArrow
        }
    }

    /// Stays possible the whole time, so it's never in anyone's way: it times a press itself
    /// and reports a hold past 0.45 s, then the press ending.
    final class Watcher: UIGestureRecognizer {
        var began: (Int) -> Bool = { _ in false }
        var ended: () -> Void = {}
        private var timer: Timer?
        private var holding = false
        private var direction = 0

        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            allowedPressTypes = [UIPress.PressType.leftArrow, .rightArrow].map { NSNumber(value: $0.rawValue) }
            allowedTouchTypes = []
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        convenience init() { self.init(target: nil, action: nil) }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            guard let press = presses.first(where: { $0.type == .leftArrow || $0.type == .rightArrow }) else { return }
            stop()
            direction = press.type == .leftArrow ? -1 : 1
            timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.holding = self.began(self.direction)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) { finish() }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) { finish() }

        /// Failing at the end of each press lets UIKit reset it for the next.
        private func finish() {
            stop()
            state = .failed
        }

        /// Ends any hold, and the timer before one.
        func stop() {
            timer?.invalidate()
            timer = nil
            if holding { ended() }
            holding = false
        }

        override func reset() {
            super.reset()
            stop()
        }
    }
}
