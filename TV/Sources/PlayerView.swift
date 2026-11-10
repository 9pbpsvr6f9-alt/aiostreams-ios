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

    let engine: AetherEngine
    let overlay: SubtitleOverlayView
    let request: PlayRequest
    private let client: JellyfinClient
    private var bag = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var reported = false
    private var stopped = false

    init(request: PlayRequest, client: JellyfinClient) {
        self.request = request
        self.client = client
        engine = SharedEngine.engine
        overlay = SubtitleOverlayView()
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

struct PlayerScreen: View {
    let request: PlayRequest
    let close: () -> Void

    @EnvironmentObject private var session: Session
    @State private var model: PlayerModel?

    var body: some View {
        Group {
            if let model {
                PlayerControls(model: model, close: finish)
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard model == nil, let client = session.client else { return }
            let player = PlayerModel(request: request, client: client)
            model = player
            player.start()
        }
    }

    private func finish() {
        model?.stop()
        close()
    }
}

private struct PlayerControls: View {
    @ObservedObject var model: PlayerModel
    let close: () -> Void

    @State private var shown = true
    @State private var tracks = false
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            VideoSurface(model: model)
                .ignoresSafeArea()

            if model.waiting && model.failure == nil {
                ProgressView().scaleEffect(1.6)
            }

            if let failure = model.failure {
                VStack(spacing: 24) {
                    Text("This version didn't play").font(.title2).bold()
                    Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Press Menu to pick another version.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(60)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
            }

            if shown && !tracks { transport }
            if tracks {
                TrackPanel(model: model) { tracks = false; focused = true; wake() }
            }
        }
        // The whole screen takes the remote while the track panel is closed.
        .focusable(!tracks)
        .focused($focused)
        .onAppear { focused = true; wake() }
        .onPlayPauseCommand { model.togglePause(); wake() }
        .onTapGesture { model.togglePause(); wake() }
        .onMoveCommand { direction in
            switch direction {
            case .left: model.skip(-10)
            case .right: model.skip(30)
            case .down: tracks = true
            default: break
            }
            wake()
        }
        .onExitCommand {
            if tracks { tracks = false; focused = true }
            else if shown && !model.paused { shown = false }
            else { close() }
        }
        .onChange(of: model.finished) { _, done in if done { close() } }
        .onChange(of: model.paused) { _, _ in wake() }
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text(model.request.item.isEpisode ? "\(model.request.item.seriesName ?? "") · \(model.request.item.displayTitle)" : (model.request.item.name ?? ""))
                .font(.title3).bold()
                .lineLimit(1)
            ProgressBar(position: model.position, duration: model.duration)
            HStack {
                Image(systemName: model.paused ? "play.fill" : "pause.fill")
                Text(clock(model.position))
                Spacer()
                Text("◀ 10s · 30s ▶ · ▼ Audio & subtitles").foregroundStyle(.secondary)
                Spacer()
                Text("-" + clock(max(model.duration - model.position, 0)))
            }
            .font(.callout.monospacedDigit())
        }
        .padding(.horizontal, 90)
        .padding(.bottom, 60)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 360)
        }
        .ignoresSafeArea()
        .transition(.opacity)
    }

    /// Shows the controls, and hides them again a few seconds into playback.
    private func wake() {
        withAnimation { shown = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !model.paused, !tracks else { return }
            withAnimation { shown = false }
        }
    }

    private func clock(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? seconds : 0)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ProgressBar: View {
    let position: Double
    let duration: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(.white.opacity(0.25))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white)
                        .frame(width: duration > 0 ? geometry.size.width * min(position / duration, 1) : 0)
                }
        }
        .frame(height: 10)
    }
}

/// Audio and subtitle choices as plain buttons; a SwiftUI `Menu` blinks in player controls on tvOS 26.
private struct TrackPanel: View {
    @ObservedObject var model: PlayerModel
    let done: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            column("Audio") {
                ForEach(model.audioTracks) { track in
                    choice(label(track), on: track.id == model.activeAudio) { model.selectAudio(track.id) }
                }
            }
            column("Subtitles") {
                choice("Off", on: model.activeSubtitle == nil) { model.selectSubtitle(nil) }
                ForEach(model.subtitleTracks) { track in
                    choice(label(track), on: track.id == model.activeSubtitle) { model.selectSubtitle(track.id) }
                }
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: 620, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .onExitCommand(perform: done)
    }

    private func column<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) { content() }
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }

    private func choice(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "checkmark").opacity(on ? 1 : 0)
                Text(text).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func label(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if !track.name.isEmpty { parts.append(track.name) }
        if let language = track.language, !language.isEmpty, !track.name.localizedCaseInsensitiveContains(language) {
            parts.append(Locale.current.localizedString(forLanguageCode: language) ?? language)
        }
        if track.isForced { parts.append("Forced") }
        if track.isExternal { parts.append("Addon") }
        return parts.isEmpty ? "Track \(track.id)" : parts.joined(separator: " · ")
    }
}
