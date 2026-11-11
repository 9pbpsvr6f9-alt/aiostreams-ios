import AetherEngine
import AVKit
import Combine
import SwiftUI

/// One engine for the app's life, as AetherEngine is built to be reused across titles.
@MainActor
enum SharedEngine {
    static let engine: AetherEngine = {
        do {
            let engine = try AetherEngine()
            // Nothing else here plays sound, so the session is released when playback ends.
            engine.deactivatesAudioSessionOnStop = true
            return engine
        } catch {
            fatalError("AetherEngine could not start: \(error)")
        }
    }()
}

/// Plays one request and reports it to the server as the web app's `PlaybackReporter` does.
@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var paused = false
    @Published private(set) var waiting = true
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var audioTracks: [TrackInfo] = []
    @Published private(set) var subtitleTracks: [TrackInfo] = []
    @Published private(set) var activeAudio: Int?
    @Published private(set) var activeSubtitle: Int?
    @Published private(set) var failure: String?
    @Published private(set) var finished = false
    @Published private(set) var chapters: [ChapterInfo] = []
    /// How far ahead of the start the stream is held, in seconds.
    @Published private(set) var buffered: Double = 0
    @Published private(set) var speed: Double = 1
    @Published private(set) var fit: Fit = .fit

    enum Fit: String, CaseIterable {
        case fit = "Fit", crop = "Crop", stretch = "Stretch"

        var gravity: AVLayerVideoGravity {
            switch self {
            case .fit: return .resizeAspect
            case .crop: return .resizeAspectFill
            case .stretch: return .resize
            }
        }
    }

    let engine: AetherEngine
    let overlay: SubtitleOverlayView
    let request: PlayRequest
    private let client: JellyfinClient
    private var bag = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var reported = false
    private var stopped = false

    private let audioLanguages: [String]
    private let subtitleLanguages: [String]

    init(request: PlayRequest, client: JellyfinClient, audioLanguages: [String] = [], subtitleLanguages: [String] = [], look: SubtitleLook = SubtitleLook()) {
        self.request = request
        self.client = client
        self.audioLanguages = audioLanguages
        self.subtitleLanguages = subtitleLanguages
        engine = SharedEngine.engine
        overlay = SubtitleOverlayView()
        overlay.look = look
        observe()
    }

    private func observe() {
        engine.$state
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .playing: self.setPaused(false)
                case .paused: self.setPaused(true)
                case .ended: self.finished = true
                case .error(let message):
                    AppLog.warn("player", "error: \(message)")
                    self.failure = message
                default: break
                }
            }
            .store(in: &bag)
        Publishers.CombineLatest3(engine.$isBuffering, engine.$isSeeking, engine.$hasFirstFrameReadyForDisplay)
            .sink { [weak self] buffering, seeking, ready in self?.waiting = buffering || seeking || !ready }
            .store(in: &bag)
        engine.clock.$currentTime
            .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.position = $0 }
            .store(in: &bag)
        engine.$duration.sink { [weak self] in self?.duration = $0 }.store(in: &bag)
        engine.$mediaChapters.sink { [weak self] in self?.chapters = $0 }.store(in: &bag)
        engine.clock.$bufferedPosition
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] in self?.buffered = $0 }
            .store(in: &bag)
        engine.$audioTracks.sink { [weak self] in self?.audioTracks = $0 }.store(in: &bag)
        engine.$subtitleTracks.sink { [weak self] in self?.subtitleTracks = $0 }.store(in: &bag)
        engine.$activeAudioTrackIndex.sink { [weak self] in self?.activeAudio = $0 }.store(in: &bag)
        engine.$activeSubtitleTrackIndex.sink { [weak self] in self?.activeSubtitle = $0 }.store(in: &bag)
        engine.$subtitleCues.sink { [weak self] in self?.overlay.setCues($0) }.store(in: &bag)
        engine.clock.$sourceTime.sink { [weak self] in self?.overlay.setTime($0) }.store(in: &bag)
        Publishers.CombineLatest(engine.$sourceVideoWidth, engine.$sourceVideoHeight)
            .sink { [weak self] width, height in
                guard let self else { return }
                let aspect = self.engine.sourceVideoPixelAspectRatio
                self.overlay.videoSize = CGSize(width: Double(width) * (aspect > 0 ? aspect : 1), height: Double(height))
            }
            .store(in: &bag)
    }

    func start() {
        guard loadTask == nil else { return }
        guard let url = client.streamURL(itemId: request.item.id, source: request.source) else {
            failure = "This version has no address to play."
            return
        }
        var options = LoadOptions()
        options.httpHeaders = request.source.requiredHttpHeaders ?? [:]
        // The engine writes the display criteria itself, following the Apple TV's Match Content setting.
        options.matchContentEnabled = Self.window?.avDisplayManager.isDisplayCriteriaMatchingEnabled ?? true
        // Serves Dolby Vision profile 8 as profile 5 on a TV without Dolby Vision; ignored on one with it.
        options.forceDolbyVisionOnNonDVDisplay = true
        options.externalSubtitles = serverSubtitles()
        // The account's languages and subtitle mode, as the web app passes them to its players.
        options.preferredAudioLanguages = audioLanguages
        options.preferredSubtitleLanguages = subtitleLanguages

        AppLog.info("player", "load \(request.item.id) source=\(request.source.ownId) host=\(url.host ?? "?")")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let start = self.request.startMs.map { $0 / 1000 }
                try await self.engine.load(url: url, startPosition: start, options: options)
                self.engine.play()
                self.report("/Sessions/Playing")
                self.progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report("/Sessions/Playing/Progress", event: "TimeUpdate") }
                }
            } catch is CancellationError {
            } catch {
                AppLog.warn("player", "load failed: \(error)")
                self.failure = error.localizedDescription
            }
        }
    }

    /// The configuration's subtitle addons' files, registered as tracks the user can pick.
    private func serverSubtitles() -> [ExternalSubtitleTrack] {
        (request.source.mediaStreams ?? []).compactMap { stream in
            guard stream.type == "Subtitle", stream.isExternal == true,
                  let address = stream.deliveryUrl, let url = client.absolute(address) else { return nil }
            return ExternalSubtitleTrack(
                url: url,
                name: stream.displayTitle ?? stream.title,
                language: stream.language,
                isForced: stream.isForced ?? false,
                httpHeaders: [:]
            )
        }
    }

    private static var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
    }

    private func setPaused(_ value: Bool) {
        let changed = value != paused
        paused = value
        if changed, reported { report("/Sessions/Playing/Progress", event: value ? "Pause" : "Unpause") }
    }

    func togglePause() { engine.togglePlayPause() }

    func seek(to seconds: Double) {
        let target = min(max(seconds, 0), max(duration - 1, 0))
        position = target
        Task { await engine.seek(to: target) }
    }

    func setSpeed(_ value: Double) {
        speed = value
        engine.setRate(Float(value))
    }

    func setFit(_ value: Fit) {
        fit = value
        engine.videoGravity = value.gravity
        overlay.gravity = value.gravity
    }

    func skip(_ seconds: Double) {
        let target = min(max(position + seconds, 0), max(duration - 1, 0))
        position = target
        Task { await engine.seek(to: target) }
    }

    func selectAudio(_ id: Int) {
        engine.selectAudioTrack(index: id)
        report("/Sessions/Playing/Progress", event: "AudioTrackChange")
    }

    func selectSubtitle(_ id: Int?) {
        if let id { engine.selectSubtitleTrack(index: id) } else { engine.clearSubtitle() }
        report("/Sessions/Playing/Progress", event: "SubtitleTrackChange")
    }

    private func body(_ extra: [String: Any] = [:]) -> [String: Any] {
        var body: [String: Any] = [
            "ItemId": request.item.id,
            "MediaSourceId": request.source.ownId,
            "PositionTicks": Int64(position * 1000 * JellyfinClient.ticksPerMs),
            "IsPaused": paused,
            "CanSeek": true,
            "PlayMethod": "DirectPlay",
        ]
        if let session = request.playSessionId { body["PlaySessionId"] = session }
        return body.merging(extra) { _, new in new }
    }

    private func report(_ path: String, event: String? = nil) {
        guard !stopped else { return }
        if path == "/Sessions/Playing" { reported = true }
        let payload = body(event.map { ["EventName": $0] } ?? [:])
        let client = client
        Task { await client.fire(path, body: payload) }
    }

    /// Saves the position on the server and hands the screen back to the app.
    func stop() {
        guard !stopped else { return }
        progressTimer?.invalidate()
        loadTask?.cancel()
        if reported {
            let payload = body()
            let client = client
            Task { await client.fire("/Sessions/Playing/Stopped", body: payload) }
        }
        stopped = true
        bag.removeAll()
        overlay.clear()
        // The plain stop returns the TV to its default mode for the app's own screens.
        engine.stop()
    }
}

/// The engine's picture with the subtitles over it.
struct VideoSurface: UIViewRepresentable {
    let model: PlayerModel

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        let video = AetherPlayerView()
        for view in [video, model.overlay] as [UIView] {
            view.frame = container.bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(view)
        }
        model.engine.bind(view: video)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

