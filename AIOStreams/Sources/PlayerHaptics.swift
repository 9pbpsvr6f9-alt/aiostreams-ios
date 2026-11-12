import UIKit

@MainActor
final class PlayerHaptics {
    var enabled = true
    private var policy = PlayerHapticPolicy()
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .soft)

    func begin(_ level: String, value: Double) {
        policy.begin(level, value: value)
        if enabled { selection.prepare() }
    }

    func tick(_ level: String, value: Double) {
        guard enabled, policy.tick(level, value: value, now: ProcessInfo.processInfo.systemUptime) else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    func action(selectionChange: Bool = false) {
        guard enabled, policy.action(now: ProcessInfo.processInfo.systemUptime) else { return }
        if selectionChange {
            selection.selectionChanged()
            selection.prepare()
        } else {
            impact.impactOccurred(intensity: 0.4)
            impact.prepare()
        }
    }
}
