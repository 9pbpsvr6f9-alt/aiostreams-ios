import AVFoundation
import AetherEngineFeatures
import SafariServices
import UIKit
import WebKit

/// The video beneath, the subtitles over it, and the page on top drawing every screen and the player's controls.
@MainActor
final class RootViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let engine: AetherEngine
    private let videoView = AetherPlayerView()
    private let overlay = SubtitleOverlayView()
    private let thumbnails = ThumbnailStore()
    private var videoStage: VideoStage!
    private let bridge = Bridge()
    private let systemVolume = SystemVolumeControl()
    private let haptics = PlayerHaptics()
    private var gesturesEnabled = true { didSet { updateVolumeIndicator() } }
    /// The full-window player is showing, where volume swipes replace iOS's volume indicator.
    private var playerFillsWindow = false { didSet { updateVolumeIndicator() } }
    /// The system volume, watched while the full player hides iOS's indicator, for the volume buttons' toast.
    private var volumeObservation: NSKeyValueObservation?
    /// When the player's own swipe last set the volume; the change it causes needs no toast.
    private var ownVolumeChangeAt: TimeInterval = -.infinity
    private var webView: WKWebView!
    private var player: PlayerChannel!
    private var pictureInPicture: PictureInPicture!
    private let pipBackdrop = UIView()

    private var brightnessBeforeSwipe: CGFloat?
    private weak var brightnessScreen: UIScreen?
    private var backgroundObserver: NSObjectProtocol?

    private var fullscreen = false
    private var linksReady = false
    private var pendingLinks: [String] = []

    init() {
        do {
            engine = try AetherEngine()
        } catch {
            fatalError("AetherEngine could not start: \(error)")
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .black
        root.overrideUserInterfaceStyle = .dark

        videoView.isHidden = true
        engine.bind(view: videoView)
        overlay.isHidden = true

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(WebAssets(thumbnails: thumbnails), forURLScheme: WebAssets.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = "AIOStreams-iOS/\(AppInfo.version)"
        configuration.websiteDataStore = .default()
        bridge.install(into: configuration.userContentController)
        if let seed = DemoMode.storageScript {
            configuration.userContentController.addUserScript(
                WKUserScript(source: seed, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.overrideUserInterfaceStyle = .dark
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        // Browsing snapshots need a painted surface, not just a dark under-page color.
        webView.underPageBackgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        bridge.webView = webView

        videoStage = VideoStage(video: videoView, subtitles: overlay)
        videoStage.needsTransparentPage = { [weak webView] transparent in
            // Refresh runs on every layout pass; only a real change repaints the page.
            guard let webView, webView.isOpaque == transparent else { return }
            webView.isOpaque = !transparent
            let color: UIColor = transparent ? .clear : .black
            webView.backgroundColor = color
            webView.scrollView.backgroundColor = color
            webView.underPageBackgroundColor = color
        }
        videoStage.fullWindowChanged = { [weak self] full in
            guard let self, self.playerFillsWindow != full else { return }
            self.playerFillsWindow = full
        }
        videoStage.web = webView
        videoStage.view.frame = root.bounds
        videoStage.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(videoStage.view)
        pipBackdrop.backgroundColor = .black
        pipBackdrop.isHidden = true
        pipBackdrop.isUserInteractionEnabled = false
        for view in [pipBackdrop, webView] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                view.topAnchor.constraint(equalTo: root.topAnchor),
                view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        videoStage.refresh()
        view = root
    }

    /// Apple's volume view hides iOS's own volume indicator while it is on screen, and the player's
    /// volume swipes need it there to set the volume. So it is there only in the full-window player
    /// with gestures on; browsing, previews and the mini player keep iOS's indicator.
    private func updateVolumeIndicator() {
        guard let root = viewIfLoaded else { return }
        if playerFillsWindow && gesturesEnabled {
            systemVolume.attach(to: root)
            if volumeObservation == nil {
                volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) {
                    [weak self] _, change in
                    guard let volume = change.newValue else { return }
                    Task { @MainActor in self?.systemVolumeChanged(Double(volume)) }
                }
            }
        } else {
            systemVolume.detach()
            volumeObservation?.invalidate()
            volumeObservation = nil
        }
    }

    /// The volume buttons moved the system volume: the page shows the swipe's toast, as iOS's own
    /// indicator is hidden in the player. A change the swipe itself made shows its own toast already.
    private func systemVolumeChanged(_ volume: Double) {
        guard playerFillsWindow, gesturesEnabled, volume.isFinite,
              ProcessInfo.processInfo.systemUptime - ownVolumeChangeAt > 0.5 else { return }
        bridge.send(["type": "system-volume", "volume": volume])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        updateVolumeIndicator()
        player = PlayerChannel(engine: engine, overlay: overlay, thumbnails: thumbnails) { [weak self] message in
            self?.bridge.send(message)
        }
        player.showVideo = { [weak self] shown in
            self?.videoView.isHidden = !shown
            self?.overlay.isHidden = !shown
            if !shown {
                self?.restoreBrightness()
                self?.videoStage.stop()
            }
        }
        pictureInPicture = PictureInPicture(engine: engine, channel: player) { [weak self] message in
            self?.bridge.send(message)
        }
        player.pipEligibilityChanged = { [weak self] in self?.pictureInPicture?.refresh() }
        pictureInPicture.changed = { [weak self] active in
            guard let self else { return }
            self.pipBackdrop.isHidden = !active
            self.overlay.isHidden = active || !self.player.hasMedia
            self.videoStage.refresh()
        }
        pictureInPicture.restore = { [weak self] in self?.view.window?.makeKeyAndVisible() }
        pictureInPicture.failed = { [weak self] in
            guard let self, self.presentedViewController == nil,
                  UIApplication.shared.applicationState == .active else { return }
            let alert = UIAlertController(title: "Picture in Picture", message: "Picture in Picture isn't available for this video right now.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
        bridge.onMessage = { [weak self] type, message in self?.handle(type, message) }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.restoreBrightness() }
        }
        webView.load(URLRequest(url: DemoMode.startURL ?? WebAssets.startURL))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoStage?.refresh()
    }

    override var prefersStatusBarHidden: Bool { fullscreen }
    override var prefersHomeIndicatorAutoHidden: Bool { fullscreen }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { fullscreen ? .all : [] }

    // MARK: - Messages

    private func handle(_ type: String, _ message: [String: Any]) {
        if type == "player-load" {
            videoStage.start(preview: JSON.flag(message["preview"]) ?? false)
            if videoStage.isPreview && fullscreen { setFullscreen(false) }
        }
        if player.handle(type, message) { return }
        switch type {
        case "app-info":
            bridge.send([
                "type": "app-info",
                "app": AppInfo.version,
                "platform": "ios",
                "mpv": NSNull(),
                "ffmpeg": NSNull(),
                "player": AppInfo.player,
            ])
        case "pip":
            if JSON.flag(message["value"]) == false { pictureInPicture.stopForRestore() }
            else { pictureInPicture.toggle() }
        case "ios-player-settings":
            if let enabled = JSON.flag(message["automaticPip"]) { pictureInPicture.automaticEnabled = enabled }
            if let enabled = JSON.flag(message["haptics"]) { haptics.enabled = enabled }
            if let enabled = JSON.flag(message["gestures"]) {
                gesturesEnabled = enabled
                if !enabled { restoreBrightness() }
            }
        case "ui-haptic":
            // Browsing, so no media is needed, unlike the player's own feedback.
            guard UIApplication.shared.applicationState == .active else { break }
            switch message["action"] as? String {
            case "menu": haptics.menu()
            case "select": haptics.select()
            default: break
            }
        case "player-haptic":
            if player.hasMedia, UIApplication.shared.applicationState == .active,
               let action = message["action"] as? String, ["toggle", "seek", "track"].contains(action) {
                haptics.action(selectionChange: action == "track")
            }
        case "levels":
            readLevels(message)
        case "set-level":
            setLevel(message)
        case "player-frame":
            if let preview = JSON.flag(message["preview"]) { player.setPreviewMode(preview) }
            videoStage.place(VideoFrame.from(message, webWidth: webView.bounds.width),
                             preview: JSON.flag(message["preview"]))
            if videoStage.isPreview && fullscreen { setFullscreen(false) }
        case "fullscreen":
            setFullscreen(JSON.flag(message["value"]) ?? !fullscreen)
        case "update-check":
            // Updates come from wherever the IPA was installed from.
            bridge.send(["type": "update-state", "state": "off", "channel": NSNull(), "version": NSNull(), "error": NSNull()])
        case "external-players":
            bridge.send(["type": "external-players", "players": [Any]()])
        case "video-output":
            bridge.send(["type": "video-output", "outputs": [Any](), "running": "system", "chosen": "system"])
        case "audio-devices":
            bridge.send(["type": "audio-devices", "devices": NSNull()])
        case "youtube-resolve":
            let request = message["request"] ?? ""
            YouTube.resolve(message["id"] as? String ?? "") { [weak self] url in
                self?.bridge.send(["type": "youtube-resolved", "request": request, "url": JSON.orNull(url)])
            }
        case "licenses":
            bridge.send(AppInfo.licenses)
        case "diagnostics":
            let text = [
                "App: AIOStreams iOS \(AppInfo.version)",
                "Device: \(AppInfo.deviceModel), iOS \(UIDevice.current.systemVersion)",
                "Web: \(message["web"] as? String ?? "?")",
                "Server: \(message["server"] as? String ?? "none")",
                player.diagnostics,
                "",
                AppLog.recent,
            ].joined(separator: "\n")
            bridge.send(["type": "diagnostics", "text": text])
        case "crash-report":
            bridge.send(["type": "crash-report"])
        case "links-ready":
            linksReady = true
            for link in pendingLinks { bridge.send(["type": "link", "url": link]) }
            pendingLinks.removeAll()
        case "save-file":
            saveFile(name: message["name"] as? String ?? "file.txt", text: message["text"] as? String ?? "")
        case "restart":
            webView.reload()
        case "log":
            let level = message["level"] as? String
            let text = message["message"] as? String ?? ""
            level == "warn" ? AppLog.warn("web", text) : AppLog.info("web", text)
        case "web-error":
            AppLog.warn("web", message["message"] as? String ?? "")
        case "exit", "open-logs", "player-key", "window-buttons", "discord-check", "external-choose",
             "external-open", "external-close", "watch-next", "keyboard-completions", "player-engine",
             "player-retry", "crash-seen", "voice-search", "voice-cancel":
            break
        default:
            AppLog.info("bridge", "unhandled \(type)")
        }
    }

    func openLink(_ url: URL) {
        guard url.scheme == WebAssets.scheme else { return }
        if linksReady, bridge.connected {
            bridge.send(["type": "link", "url": url.absoluteString])
        } else {
            pendingLinks.append(url.absoluteString)
        }
    }

    private var playerScreen: UIScreen {
        view.window?.windowScene?.screen ?? UIScreen.main
    }

    private func readLevels(_ message: [String: Any]) {
        var volume = systemVolume.value
        if gesturesEnabled, message["level"] as? String == "volume", player.hasMedia,
           UIApplication.shared.applicationState == .active,
           let start = SwipeVolume.start(system: volume, player: player.effectivePlaybackVolume),
           markOwnVolumeChange(),
           systemVolume.set(start) {
            // Lower system volume BEFORE removing player attenuation. This happens once,
            // on the initial read for a volume swipe, never for a brightness swipe.
            player.prepareForSystemVolumeControl()
            // outputVolume may publish asynchronously; the gesture needs the normalized
            // starting value, not the previous system value, to avoid a first-move jump.
            volume = start
        }
        if gesturesEnabled, let level = message["level"] as? String,
           ["volume", "brightness"].contains(level) {
            haptics.begin(level, value: level == "volume" ? volume : Double(playerScreen.brightness))
        }
        bridge.send(["type": "levels", "volume": volume,
                     "brightness": Double(playerScreen.brightness)])
    }

    private func setLevel(_ message: [String: Any]) {
        guard let level = message["level"] as? String else { return }
        // The web player releases its temporary brightness when its gesture layer unmounts.
        if level == "brightness", message["value"] is NSNull {
            restoreBrightness()
            return
        }
        guard gesturesEnabled, player.hasMedia, UIApplication.shared.applicationState == .active,
              let value = JSON.number(message["value"]) else { return }
        let clamped = min(max(value, 0), 1)
        if level == "volume" {
            markOwnVolumeChange()
            if systemVolume.set(clamped) {
                haptics.tick(level, value: clamped)
            } else {
                AppLog.info("player", "System volume is not adjustable on the current audio route")
            }
        } else if level == "brightness" {
            let screen = playerScreen
            if brightnessScreen !== screen {
                restoreBrightness()
                brightnessScreen = screen
                brightnessBeforeSwipe = screen.brightness
            }
            screen.brightness = CGFloat(clamped)
            haptics.tick(level, value: clamped)
        }
    }

    /// Notes that the swipe is about to set the volume, so its change shows no second toast.
    @discardableResult
    private func markOwnVolumeChange() -> Bool {
        ownVolumeChangeAt = ProcessInfo.processInfo.systemUptime
        return true
    }

    private func restoreBrightness() {
        if let screen = brightnessScreen, let original = brightnessBeforeSwipe {
            screen.brightness = original
        }
        brightnessBeforeSwipe = nil
        brightnessScreen = nil
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
    }

    private func setFullscreen(_ on: Bool) {
        guard !on || !videoStage.isPreview else { return }
        fullscreen = on
        AppDelegate.orientations = on ? .landscape : .allButUpsideDown
        setNeedsUpdateOfSupportedInterfaceOrientations()
        if let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: on ? .landscape : .allButUpsideDown)) { error in
                AppLog.info("app", "orientation: \(error.localizedDescription)")
            }
        }
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        bridge.send(["type": "fullscreen", "value": on])
    }

    private func saveFile(name: String, text: String) {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        guard (try? text.write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        let share = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = view
        share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(share, animated: true)
    }

    private func openExternally(_ url: URL) {
        if url.scheme == "http" || url.scheme == "https" {
            present(SFSafariViewController(url: url), animated: true)
        } else {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        let ours = url.scheme == WebAssets.scheme && url.host == "localhost"
        // Frames the page embeds (trailers, sign-in pages) load in place; anything else leaves the app.
        if ours || url.scheme == "about" || navigationAction.targetFrame?.isMainFrame == false {
            return decisionHandler(.allow)
        }
        openExternally(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        restoreBrightness()
        bridge.pageLoading()
        linksReady = false
        player?.pageLoading()
        if fullscreen { setFullscreen(false) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        restoreBrightness()
        AppLog.warn("app", "the page's process ended; loading it again")
        player?.pageLoading()
        webView.reload()
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { openExternally(url) }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}
