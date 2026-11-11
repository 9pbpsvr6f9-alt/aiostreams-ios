import AetherEngineFeatures
import MediaPlayer
import UIKit

/// The lock screen's and Control Center's view of what plays, whose buttons go to the page as `media-key`.
@MainActor
final class NowPlaying {
    var onKey: ([String: Any]) -> Void = { _ in }

    private let engine: AetherEngine
    private var info: [String: Any] = [:]
    private var artworkURL: String?
    private var registered = false

    init(engine: AetherEngine) {
        self.engine = engine
    }

    func setItem(_ item: [String: Any]?) {
        guard let item, let title = item["title"] as? String else {
            info = [:]
            artworkURL = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        register()
        var next: [String: Any] = [MPMediaItemPropertyTitle: title, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue]
        if let subtitle = item["subtitle"] as? String { next[MPMediaItemPropertyArtist] = subtitle }
        if let artwork = info[MPMediaItemPropertyArtwork], item["artwork"] as? String == artworkURL {
            next[MPMediaItemPropertyArtwork] = artwork
        }
        info = next
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = JSON.flag(item["next"]) ?? false
        center.previousTrackCommand.isEnabled = JSON.flag(item["previous"]) ?? false
        if let artwork = item["artwork"] as? String, artwork != artworkURL {
            artworkURL = artwork
            loadArtwork(artwork)
        }
        update(playing: engine.state == .playing)
    }

    func update(playing: Bool) {
        guard !info.isEmpty else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine.currentTime
        if engine.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = engine.duration }
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    private func loadArtwork(_ address: String) {
        guard let url = URL(string: address) else { return }
        Task { [weak self] in
            guard let response = try? await URLSession.shared.data(from: url), let image = UIImage(data: response.0) else { return }
            guard let self, self.artworkURL == address, !self.info.isEmpty else { return }
            self.info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.info
        }
    }

    private func register() {
        guard !registered else { return }
        registered = true
        let center = MPRemoteCommandCenter.shared()
        let press = { [weak self] (key: [String: Any]) -> MPRemoteCommandHandlerStatus in
            MainActor.assumeIsolated { self?.onKey(key) }
            return .success
        }
        center.playCommand.addTarget { _ in press(["action": "play"]) }
        center.pauseCommand.addTarget { _ in press(["action": "pause"]) }
        center.togglePlayPauseCommand.addTarget { _ in press(["action": "toggle"]) }
        center.stopCommand.addTarget { _ in press(["action": "stop"]) }
        center.nextTrackCommand.addTarget { _ in press(["action": "next"]) }
        center.previousTrackCommand.addTarget { _ in press(["action": "previous"]) }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { _ in press(["action": "skip", "offset": 10_000]) }
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { _ in press(["action": "skip", "offset": -10_000]) }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return press(["action": "seek", "position": event.positionTime * 1000])
        }
    }
}
