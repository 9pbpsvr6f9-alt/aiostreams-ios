import AVFoundation
import MediaPlayer
import UIKit

/// Reads the current audio route's volume and uses Apple's standard volume control to adjust it.
/// No private selectors, key paths or AVAudioSession outputVolume writes.
@MainActor
final class SystemVolumeControl {
    private let control = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 200, height: 40))

    var value: Double { Double(AVAudioSession.sharedInstance().outputVolume) }

    func attach(to parent: UIView) {
        // MPVolumeView must stay in the view hierarchy for its system slider to be connected.
        // The web player supplies the visible gesture area and percentage indicator.
        control.showsVolumeSlider = true
        control.showsRouteButton = false
        control.isUserInteractionEnabled = false
        control.accessibilityElementsHidden = true
        if control.superview !== parent { parent.addSubview(control) }
    }

    /// While attached, iOS hides its own volume indicator, so it is attached only in the player.
    func detach() {
        control.removeFromSuperview()
    }

    @discardableResult
    func set(_ value: Double) -> Bool {
        guard value.isFinite, control.window != nil else { return false }
        control.layoutIfNeeded()
        guard let slider = control.subviews.compactMap({ $0 as? UISlider }).first,
              slider.isEnabled else {
            // Some routes have a fixed volume. Do not silently fall back to changing player gain.
            return false
        }
        slider.setValue(Float(min(max(value, 0), 1)), animated: false)
        slider.sendActions(for: .valueChanged)
        slider.sendActions(for: .touchUpInside)
        return true
    }
}
