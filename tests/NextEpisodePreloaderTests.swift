actor WarmRecorder {
    var starts: [String] = []
    var cancelled = 0
    func warm(_ url: URL, _ headers: [String: String]) async {
        starts.append(url.absoluteString + (headers["Test"] ?? ""))
        do { try await Task.sleep(for: .seconds(30)) }
        catch { cancelled += 1 }
    }
    func counts() -> (Int, Int) { (starts.count, cancelled) }
}
let recorder = WarmRecorder()
let loader = await MainActor.run {
    NextEpisodePreloader { url, headers in await recorder.warm(url, headers) }
}
func prepare(_ address: String?, _ headers: [String: String] = [:], allowed: Bool = true) async {
    await loader.prepare(address, headers: headers, allowed: allowed)
    // Yield until the detached task can enter the recorder.
    try? await Task.sleep(for: .milliseconds(50))
}
await prepare("https://example.invalid/next", ["Test": "a"])
await prepare("https://example.invalid/next", ["Test": "a"])
var counts = await recorder.counts()
precondition(counts.0 == 1 && counts.1 == 0, "Duplicate countdown reports must not restart the fetch")
await prepare("https://example.invalid/next", ["Test": "b"])
counts = await recorder.counts()
precondition(counts.0 == 2 && counts.1 == 1, "Changed authorization must replace the fetch")
await prepare(nil)
counts = await recorder.counts()
precondition(counts.1 == 2, "Dismissing the countdown must cancel unfinished work")
await prepare("file:///private/video")
await prepare("https://example.invalid/live", allowed: false)
counts = await recorder.counts()
precondition(counts.0 == 2, "Local files, live video and trailers must not fetch")
await prepare("https://example.invalid/another")
await loader.cancel()
try? await Task.sleep(for: .milliseconds(50))
counts = await recorder.counts()
precondition(counts.0 == 3 && counts.1 == 3, "Stop/reload must cancel the fetch")
print("Next episode preloader tests passed")
