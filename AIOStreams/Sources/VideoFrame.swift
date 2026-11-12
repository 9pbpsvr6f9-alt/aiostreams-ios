import Foundation
import CoreFoundation
import CoreGraphics

/// Native placement of a page's trailer or mini player. Coordinates include the viewport zoom.
struct VideoFrame: Equatable {
    let rect: CGRect
    let hidden: Bool
    let animate: Bool
    let radius: CGFloat
    let bottomRadius: CGFloat
    let subtitles: Bool

    static func from(_ message: [String: Any], webWidth: CGFloat) -> VideoFrame? {
        guard let frame = message["frame"] as? [String: Any] else { return nil }
        func number(_ value: Any?) -> Double? {
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
            return n.doubleValue
        }
        guard let pageWidth = number(message["pageWidth"]), pageWidth > 0,
              webWidth.isFinite, webWidth > 0,
              let x = number(frame["x"]), let y = number(frame["y"]),
              let width = number(frame["width"]), let height = number(frame["height"]),
              width >= 0, height >= 0 else { return nil }
        let scale = webWidth / CGFloat(pageWidth)
        guard scale.isFinite, scale >= 0.01, scale <= 100 else { return nil }
        func points(_ n: Double) -> CGFloat { CGFloat(min(max(n, -100_000), 100_000)) * scale }
        return VideoFrame(
            rect: CGRect(x: points(x), y: points(y), width: points(width), height: points(height)),
            hidden: frame["hidden"] as? Bool ?? false,
            animate: frame["animate"] as? Bool ?? false,
            radius: max(0, points(number(frame["radius"]) ?? 0)),
            bottomRadius: max(0, points(number(frame["bottomRadius"]) ?? 0)),
            subtitles: frame["subtitles"] as? Bool ?? true
        )
    }
}
