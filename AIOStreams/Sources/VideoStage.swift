import UIKit

/**
 * The video and its subtitles, which the page can draw small: its mini player docked in a page's
 * preview, and trailers playing by themselves in cards, the hero and title pages (upstream's
 * `features/player/mini-player.tsx` and `features/trailers/preview.tsx`). As the Android app's
 * MiniPlayer does, the stage shrinks to the frame beneath the page, and while the frame isn't hidden a
 * rounded hole is cut through the page (a mask on the web view) so the video shows even where the
 * page draws. The web view keeps touch handling, including taps and drags on the iOS mini player.
 */
@MainActor
final class VideoStage {
    /// Holds the video view and the subtitle overlay, which follow its bounds.
    let view = UIView()
    /// The page, which the hole is cut through.
    weak var web: UIView? {
        didSet { refresh(animated: false) }
    }

    private let video: UIView
    private let subtitles: UIView
    private let hole = CAShapeLayer()
    private var presentation = VideoPresentation()
    private var frame: VideoFrame? { presentation.frame }
    var isPreview: Bool { presentation.preview }
    private var animator: UIViewPropertyAnimator?

    /// As the page's card moves (`MINI_MOVE_MS`, `MINI_MOVE_EASE`).
    private static let moveSeconds: TimeInterval = 0.22
    private static let moveCurve = (CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.2, y: 1))

    init(video: UIView, subtitles: UIView) {
        self.video = video
        self.subtitles = subtitles
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        for pane in [video, subtitles] {
            pane.frame = view.bounds
            pane.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(pane)
        }
        hole.fillRule = .evenOdd
        hole.fillColor = UIColor.black.cgColor
    }

    func start(preview: Bool) {
        presentation.start(preview: preview)
        refresh()
    }

    func stop() {
        presentation.stop()
        refresh()
    }

    /// Only an explicit presentation change may expand an automatic preview.
    func place(_ next: VideoFrame?, preview: Bool?) {
        presentation.place(next, preview: preview)
        refresh(animated: next?.animate == true)
    }

    /// Lays the stage and the hole out again, after a layout or orientation change.
    func refresh(animated: Bool = false) {
        guard let container = view.superview else { return }
        animator?.stopAnimation(true)
        animator = nil
        view.isHidden = !presentation.visible
        let shown = frame.flatMap { $0.visibleRect.isEmpty || $0.visibleRect.isNull ? nil : $0 }
        let target: CGRect
        if let shown, let web {
            target = container.convert(shown.visibleRect, from: web)
        } else {
            target = container.bounds
        }
        // Full screen it follows the window as before; boxed it stays where the page put it.
        view.autoresizingMask = shown == nil ? [.flexibleWidth, .flexibleHeight] : []
        view.clipsToBounds = shown != nil
        view.layer.cornerRadius = shown.map { max($0.radius, $0.bottomRadius) } ?? 0
        view.layer.maskedCorners = Self.corners(shown)
        subtitles.alpha = shown?.subtitles == false ? 0 : 1
        if animated, shown != nil {
            let (c1, c2) = Self.moveCurve
            let animator = UIViewPropertyAnimator(
                duration: Self.moveSeconds,
                timingParameters: UICubicTimingParameters(controlPoint1: c1, controlPoint2: c2)
            )
            animator.addAnimations { [view] in view.frame = target }
            animator.startAnimation()
            self.animator = animator
        } else {
            view.frame = target
        }
        let content = shown.map {
            CGRect(x: $0.rect.minX - $0.visibleRect.minX, y: $0.rect.minY - $0.visibleRect.minY,
                   width: $0.rect.width, height: $0.rect.height)
        } ?? CGRect(origin: .zero, size: target.size)
        video.frame = presentation.preview ? PreviewLayout.contentRect(in: target.size) : content
        subtitles.frame = content
        cutHole(presentation.visible ? shown : nil, animated: animated)
    }

    /// The corners the radius applies to: the bar's video has a bottom radius of its own, a docked
    /// preview's is the same all round.
    private static func corners(_ frame: VideoFrame?) -> CACornerMask {
        guard let frame else { return [] }
        var corners: CACornerMask = []
        if frame.radius > 0 { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if frame.bottomRadius > 0 { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        return corners
    }

    /// Cuts the frame's box out of the page, or puts the page back whole.
    private func cutHole(_ frame: VideoFrame?, animated: Bool) {
        guard let web else { return }
        guard let frame, !frame.hidden, !frame.visibleRect.isEmpty, !frame.visibleRect.isNull else {
            if web.layer.mask === hole { web.layer.mask = nil }
            return
        }
        let path = UIBezierPath(rect: web.bounds)
        var corners: UIRectCorner = []
        if frame.radius > 0 { corners.formUnion([.topLeft, .topRight]) }
        if frame.bottomRadius > 0 { corners.formUnion([.bottomLeft, .bottomRight]) }
        let radius = max(frame.radius, frame.bottomRadius)
        path.append(UIBezierPath(
            roundedRect: frame.visibleRect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        ))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hole.frame = web.bounds
        if animated, web.layer.mask === hole, let from = hole.path {
            let move = CABasicAnimation(keyPath: "path")
            move.fromValue = from
            move.toValue = path.cgPath
            move.duration = Self.moveSeconds
            let (c1, c2) = Self.moveCurve
            move.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(c1.x), Float(c1.y), Float(c2.x), Float(c2.y)
            )
            hole.add(move, forKey: "path")
        }
        hole.path = path.cgPath
        if web.layer.mask !== hole { web.layer.mask = hole }
        CATransaction.commit()
    }
}
