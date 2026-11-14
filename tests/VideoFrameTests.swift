// Run with VideoFrame.swift, without UIKit or engine dependencies.
let frame: [String: Any] = ["x": 40, "y": 20, "width": 320, "height": 180,
                             "radius": 16, "bottomRadius": 8, "subtitles": false]
let message: [String: Any] = ["frame": frame, "pageWidth": 800]
let placed = VideoFrame.from(message, webWidth: 400)!
precondition(placed.rect == CGRect(x: 20, y: 10, width: 160, height: 90))
precondition(placed.radius == 8 && placed.bottomRadius == 4 && !placed.subtitles)
precondition(VideoFrame.from(["frame": NSNull()], webWidth: 400) == nil)
precondition(VideoFrame.from(["frame": frame, "pageWidth": 0], webWidth: 400) == nil)
precondition(VideoFrame.from(message, webWidth: .nan) == nil)
var invalid = frame
invalid["x"] = Double.infinity
precondition(VideoFrame.from(["frame": invalid, "pageWidth": 800], webWidth: 400) == nil)
invalid = frame; invalid["width"] = -1
precondition(VideoFrame.from(["frame": invalid, "pageWidth": 800], webWidth: 400) == nil)
invalid = frame; invalid["x"] = true
precondition(VideoFrame.from(["frame": invalid, "pageWidth": 800], webWidth: 400) == nil)
// A frame measured at a scroll carries it, in points; one without it has none.
var scrolled = frame; scrolled["scrollY"] = 300
precondition(VideoFrame.from(["frame": scrolled, "pageWidth": 800], webWidth: 400)!.scrollY == 150)
precondition(placed.scrollY == nil)
var hidden = frame; hidden["hidden"] = true
precondition(VideoFrame.from(["frame": hidden, "pageWidth": 800], webWidth: 400)!.hidden)
print("Video frame placement tests passed")

// A cover picture can span the whole phone while only a small poster rectangle is visible.
var cover: [String: Any] = ["x": -400, "y": -200, "width": 1600, "height": 900,
                            "clip": ["x": 40, "y": 100, "width": 320, "height": 180]]
let clipped = VideoFrame.from(["frame": cover, "pageWidth": 800], webWidth: 400)!
precondition(clipped.visibleRect == CGRect(x: 20, y: 50, width: 160, height: 90))
cover["clip"] = ["x": 0, "y": 0, "width": Double.nan, "height": 10]
precondition(VideoFrame.from(["frame": cover, "pageWidth": 800], webWidth: 400) == nil)

var presentation = VideoPresentation()
presentation.start(preview: true)
precondition(!presentation.visible, "Autoplay must not draw fullscreen while waiting for placement")
presentation.place(clipped, preview: true)
precondition(presentation.visible && presentation.preview)
presentation.start(preview: true)
precondition(presentation.visible, "Changing trailers in one poster must preserve placement")
presentation.place(nil, preview: true)
precondition(!presentation.visible, "A cleared or rejected preview frame must hide, never expand")
presentation.place(nil, preview: nil)
precondition(!presentation.visible && presentation.preview, "A legacy frame reset must not expand autoplay")
presentation.place(nil, preview: false)
precondition(presentation.visible && !presentation.preview, "Explicitly opening the trailer may expand it")
presentation.stop()
presentation.place(clipped, preview: true)
precondition(!presentation.visible, "A late frame must not resurrect stopped playback")
presentation.start(preview: true)
precondition(presentation.visible, "A frame received before load must survive startup")
presentation.start(preview: false)
precondition(presentation.visible && presentation.frame == nil, "A regular movie must fill the player again")
print("Autoplay preview clipping and presentation regression tests passed")

// The preview fills portrait posters and wide hero artwork without stretching the source.
for size in [CGSize(width: 390, height: 520), CGSize(width: 844, height: 480), CGSize(width: 1200, height: 300)] {
    let content = PreviewLayout.contentRect(in: size)
    precondition(content.minX <= 0.0001 && content.minY <= 0.0001)
    precondition(content.maxX >= size.width - 0.0001 && content.maxY >= size.height - 0.0001)
    precondition(abs(content.midX - size.width / 2) < 0.0001)
    precondition(abs(content.midY - size.height / 2) < 0.0001)
    // A 2.39:1 trailer letterboxed inside a 16:9 encode: aspect-fill trims the encoded black bands.
    let encoded = CGSize(width: 1920, height: 1080)
    let scale = max(content.width / encoded.width, content.height / encoded.height)
    let pictureHeight = encoded.width / PreviewLayout.aspect * scale
    precondition(pictureHeight >= size.height - 0.0001, "Letterbox pixels must stay outside the artwork")
}
precondition(PreviewLayout.contentRect(in: .zero) == .zero)
print("Preview artwork cover and letterbox crop tests passed")

// The page is opaque while browsing, for WebKit's back-swipe snapshots, but video must never sit
// beneath an opaque page that hasn't been cut away (the 0.2.47 hero and title trailer regression).
var stage = VideoPresentation()
precondition(!stage.needsTransparentPage, "Browsing keeps the page opaque")
stage.start(preview: false)
precondition(stage.needsTransparentPage && !stage.cutsMask, "Full-window playback shows through the page")
var boxed = frame; boxed["hidden"] = false
stage.start(preview: true)
stage.place(VideoFrame.from(["frame": boxed, "pageWidth": 800], webWidth: 400), preview: true)
precondition(stage.cutsMask && !stage.needsTransparentPage, "A masked card preview keeps the page opaque")
stage.place(VideoFrame.from(["frame": hidden, "pageWidth": 800], webWidth: 400), preview: true)
precondition(!stage.cutsMask && stage.needsTransparentPage,
             "A hero or title trailer under the page must show through its video hole")
stage.place(nil, preview: true)
precondition(!stage.needsTransparentPage, "A cleared preview hides, and the page goes opaque again")
stage.stop()
precondition(!stage.needsTransparentPage, "Stopped playback restores the opaque page")
print("Page transparency regression tests passed")

// iOS's own volume indicator is hidden only while the player fills the window, where volume
// swipes replace it; browsing, trailer previews and the mini player keep it.
var screen = VideoPresentation()
precondition(!screen.isFullWindow, "Browsing shows iOS's volume indicator")
screen.start(preview: false)
precondition(screen.isFullWindow, "The full player hides it for its volume swipes")
screen.place(VideoFrame.from(["frame": boxed, "pageWidth": 800], webWidth: 400), preview: false)
precondition(!screen.isFullWindow, "The docked mini player keeps it")
screen.place(nil, preview: false)
precondition(screen.isFullWindow, "Expanding the mini player again hides it")
screen.start(preview: true)
screen.place(VideoFrame.from(["frame": boxed, "pageWidth": 800], webWidth: 400), preview: true)
precondition(!screen.isFullWindow, "A trailer preview keeps it")
screen.stop()
precondition(!screen.isFullWindow, "Stopping playback shows it again")
print("Volume indicator placement tests passed")
