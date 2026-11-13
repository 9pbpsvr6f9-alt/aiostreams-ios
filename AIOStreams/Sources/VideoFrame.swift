import Foundation
import CoreFoundation
import CoreGraphics

/// Native placement of a page's trailer or mini player. Coordinates include the viewport zoom.
struct VideoFrame: Equatable {
    let rect: CGRect
    let clip: CGRect?
    let hidden: Bool
    let animate: Bool
    let radius: CGFloat
    let bottomRadius: CGFloat
    let subtitles: Bool

    /// The cover picture can be much bigger than its poster. Only this part may be drawn.
    var visibleRect: CGRect { clip.map { rect.intersection($0) } ?? rect }

    static func from(_ message: [String: Any], webWidth: CGFloat) -> VideoFrame? {
        guard let frame = message["frame"] as? [String: Any] else { return nil }
        func number(_ value: Any?) -> Double? {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        guard let pageWidth = number(message["pageWidth"]), pageWidth > 0,
              webWidth.isFinite, webWidth > 0 else { return nil }
        let scale = webWidth / CGFloat(pageWidth)
        guard scale.isFinite, scale >= 0.01, scale <= 100 else { return nil }
        func points(_ n: Double) -> CGFloat { CGFloat(min(max(n, -100_000), 100_000)) * scale }
        func rectangle(_ object: [String: Any]) -> CGRect? {
            guard let x = number(object["x"]), let y = number(object["y"]),
                  let width = number(object["width"]), let height = number(object["height"]),
                  width >= 0, height >= 0 else { return nil }
            return CGRect(x: points(x), y: points(y), width: points(width), height: points(height))
        }
        guard let rect = rectangle(frame) else { return nil }
        var clip: CGRect?
        if let value = frame["clip"] {
            guard let object = value as? [String: Any], let valid = rectangle(object) else { return nil }
            clip = valid
        }
        return VideoFrame(
            rect: rect, clip: clip,
            hidden: frame["hidden"] as? Bool ?? false,
            animate: frame["animate"] as? Bool ?? false,
            radius: max(0, points(number(frame["radius"]) ?? 0)),
            bottomRadius: max(0, points(number(frame["bottomRadius"]) ?? 0)),
            subtitles: frame["subtitles"] as? Bool ?? true
        )
    }
}

/// A missing/cleared frame must never promote an automatic preview to full-window playback.
struct VideoPresentation {
    private(set) var active = false
    private(set) var preview = false
    private(set) var frame: VideoFrame?

    var visible: Bool {
        active && (!preview || (frame.map { !$0.visibleRect.isEmpty && !$0.visibleRect.isNull } ?? false))
    }

    mutating func start(preview: Bool) {
        if !preview || !self.preview { frame = nil }
        self.preview = preview
        active = true
    }

    mutating func place(_ frame: VideoFrame?, preview: Bool?) {
        if let preview { self.preview = preview }
        self.frame = frame
    }

    mutating func stop() {
        active = false
        preview = false
        frame = nil
    }

    /// The native mask cuts the frame out of the page: a shown mini player or boxed preview.
    var cutsMask: Bool {
        visible && (frame.map { !$0.hidden && !$0.visibleRect.isEmpty && !$0.visibleRect.isNull } ?? false)
    }

    /// Visible video the mask doesn't reveal shows only through a transparent page: full-window
    /// playback, and hero and title trailers, which play under the page and show through its own
    /// video hole (their frames come `hidden`). Browsing and masked video keep the page opaque.
    var needsTransparentPage: Bool { visible && !cutsMask }
}

/// A centered cinema-width canvas removes conventional 16:9 trailer letterboxing, then the stage
/// clips it to the artwork. It is preview-only; full playback keeps the user's own fit setting.
enum PreviewLayout {
    static let aspect: CGFloat = 2.39

    static func contentRect(in size: CGSize) -> CGRect {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .zero }
        let width = max(size.width, size.height * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }
}
