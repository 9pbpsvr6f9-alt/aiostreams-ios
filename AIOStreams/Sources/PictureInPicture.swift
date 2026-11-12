import AetherEngineFeatures
@preconcurrency import AVKit
import Combine
import UIKit

/// AVKit owns the floating window. Controllers are prepared while inline video is visible, so iOS
/// can start PiP during a real app switch. Merely opening a notification or Control Center is not
/// treated as leaving the app. Automatic trailer previews never qualify.
@MainActor
final class PictureInPicture: NSObject {
    private let engine: AetherEngine
    private let channel: PlayerChannel
    private let send: ([String: Any]) -> Void
    private var controller: AVPictureInPictureController?
    private var sourceKey: ObjectIdentifier?
    private var softwareSource: SoftwarePiPSource?
    private var retired: [ObjectIdentifier: (AVPictureInPictureController, SoftwarePiPSource?)] = [:]
    private var bag = Set<AnyCancellable>()
    private var starting = false
    private var restoring = false
    private var wasActive = false
    private var backgrounded = false
    private var manualRequest = false
    var automaticEnabled = true { didSet { refresh() } }
    var changed: (Bool) -> Void = { _ in }
    var restore: () -> Void = {}
    var failed: () -> Void = {}

    init(engine: AetherEngine, channel: PlayerChannel, send: @escaping ([String: Any]) -> Void) {
        self.engine = engine
        self.channel = channel
        self.send = send
        super.init()
        engine.$currentAVPlayer.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &bag)
        engine.$softwarePiPSource.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &bag)
        engine.$state.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &bag)
        engine.$hasFirstFrameReadyForDisplay.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }.store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                self.backgrounded = true
            }.store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let returned = self.backgrounded
                self.backgrounded = false
                if returned && self.active { self.stopForRestore() }
                self.refresh()
            }.store(in: &bag)
    }

    var active: Bool { controller?.isPictureInPictureActive == true }
    private var policy: PictureInPicturePolicy {
        PictureInPicturePolicy(supported: AVPictureInPictureController.isPictureInPictureSupported(),
                               hasMedia: channel.hasMedia, preview: channel.isPreview,
                               playing: engine.state == .playing,
                               sourceAvailable: engine.nativePlayerLayer != nil || engine.softwarePiPSource != nil,
                               automaticEnabled: automaticEnabled)
    }

    func refresh() {
        guard policy.prepares else { clear(); return }
        let native = engine.nativePlayerLayer
        let software = native == nil ? engine.softwarePiPSource : nil
        let key = native.map { ObjectIdentifier($0) } ?? software.map { ObjectIdentifier($0.layer) }
        if key != sourceKey {
            clear()
            sourceKey = key
            softwareSource = software // AVKit's sample-buffer content source holds its delegate weakly.
            controller = native.flatMap { AVPictureInPictureController(playerLayer: $0) }
                ?? software?.makePictureInPictureController()
            controller?.delegate = self
        }
        // AVKit owns automatic entry and honors iOS's Start PiP Automatically preference.
        // Do not emulate a manual button press from didEnterBackground to override that setting.
        controller?.canStartPictureInPictureAutomaticallyFromInline = policy.automatic
    }

    func toggle() {
        guard !starting else { return }
        if active { stopForRestore(); return }
        refresh()
        guard policy.prepares, let controller, controller.isPictureInPicturePossible else { failed(); return }
        manualRequest = true
        starting = true
        controller.startPictureInPicture()
    }

    func stopForRestore() {
        restoring = true
        controller?.stopPictureInPicture()
    }

    func clear() {
        if let controller {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
            if controller.isPictureInPictureActive || starting {
                retired[ObjectIdentifier(controller)] = (controller, softwareSource)
                controller.stopPictureInPicture()
            } else { controller.delegate = nil }
        }
        controller = nil
        sourceKey = nil
        softwareSource = nil
        starting = false
        restoring = false
        wasActive = false
        manualRequest = false
        setActive(false)
    }

    private func setActive(_ on: Bool) {
        engine.pictureInPictureActive = on
        if !on { engine.setNativeSubtitleRendering(false) }
        changed(on)
        send(["type": "pip", "value": on])
    }
}

extension PictureInPicture: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard controller === self.controller else { controller.stopPictureInPicture(); return }
        starting = true
        restoring = false
        engine.pictureInPictureActive = true // Arm the engine before its background lifecycle decision.
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        guard controller === self.controller else { controller.stopPictureInPicture(); return }
        starting = false
        manualRequest = false
        wasActive = true
        setActive(true)
        engine.setNativeSubtitleRendering(true)
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard controller === self.controller else { retired.removeValue(forKey: ObjectIdentifier(controller)); return }
        let report = manualRequest
        starting = false
        manualRequest = false
        wasActive = false
        setActive(false)
        if report { failed() }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        guard controller === self.controller else { retired.removeValue(forKey: ObjectIdentifier(controller)); return }
        let pause = PictureInPicturePolicy.pausesWhenStopped(wasActive: wasActive, restoring: restoring)
        starting = false
        wasActive = false
        restoring = false
        setActive(false)
        if pause { channel.pauseFromPictureInPicture() }
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard controller === self.controller else { completionHandler(false); return }
        restoring = true
        restore()
        changed(false)
        send(["type": "pip", "value": false])
        completionHandler(true)
    }
}
