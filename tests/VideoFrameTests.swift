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
var hidden = frame; hidden["hidden"] = true
precondition(VideoFrame.from(["frame": hidden, "pageWidth": 800], webWidth: 400)!.hidden)
print("Video frame placement tests passed")
