// Run with DownloadPlaces.swift, without UIKit: where a download's files may go.
import Foundation

let root = URL(fileURLWithPath: "/tmp/aiostreams-downloads-test", isDirectory: true)
func refused(_ relative: String) -> Bool { (try? DownloadPlaces.place(root, relative)) == nil }

// Ordinary show, film and subtitle paths land inside the folder.
let episode = try! DownloadPlaces.place(root, "Ted Lasso/Season 4/Ted Lasso S04E06.mkv")
precondition(episode.path == "/tmp/aiostreams-downloads-test/Ted Lasso/Season 4/Ted Lasso S04E06.mkv")
precondition(!refused("Film (2026)/Film (2026).en.srt"))
precondition(!refused("Show/poster.jpg") && !refused("Show/details.json"))

// Nothing may leave the folder or hide behind odd names.
precondition(refused("../escape.mkv"), "parent directory")
precondition(refused("Show/../../escape.mkv"), "nested parent directory")
precondition(refused("./here.mkv") && refused("a//b.mkv"), "empty and dot parts")
precondition(refused(""), "no name")
precondition(refused("Show/CON.mkv") && refused("Show/lpt1.srt"), "reserved names")
precondition(refused("Show/trailing. /x.mkv") && refused("Show/x.mkv."), "trailing dot or space")
precondition(refused("Show/a:b.mkv") && refused("Show/a\u{7}b.mkv"), "reserved and control characters")
precondition(refused("Show/" + String(repeating: "x", count: 201) + ".mkv"), "over-long part")

// Only media, subtitle, image and details files.
precondition(refused("Show/script.sh") && refused("Show/page.html") && refused("Show/noextension"))
precondition(!refused("Show/EPISODE.MKV"), "extensions match in any case")

// Partial files sit beside their target.
precondition(DownloadPlaces.part(of: episode).lastPathComponent == "Ted Lasso S04E06.mkv.part")

// Playback opens only files inside the folder, by path or file URL.
precondition(DownloadPlaces.isInside(root, episode.path))
precondition(DownloadPlaces.isInside(root, episode.absoluteString), "file URL")
precondition(!DownloadPlaces.isInside(root, "/tmp/aiostreams-downloads-test"), "the folder itself")
precondition(!DownloadPlaces.isInside(root, "/tmp/aiostreams-downloads-test-other/x.mkv"), "a sibling with the same prefix")
precondition(!DownloadPlaces.isInside(root, "/tmp/aiostreams-downloads-test/../etc/passwd"), "escaping by ..")
precondition(!DownloadPlaces.isInside(root, "https://example.invalid/x.mkv") && !DownloadPlaces.isInside(root, "relative/x.mkv"))
print("Download file placement tests passed")
