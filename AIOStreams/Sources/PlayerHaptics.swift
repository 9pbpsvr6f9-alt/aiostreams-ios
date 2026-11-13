import UIKit

@MainActor
final class PlayerHaptics {
    var enabled = true
    private var policy = PlayerHapticPolicy()
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private let menuImpact = UIImpactFeedbackGenerator(style: .light)

    func begin(_ level: String, value: Double) {
        policy.begin(level, value: value)
        if enabled { selection.prepare() }
    }

    func tick(_ level: String, value: Double) {
        guard enabled, policy.tick(level, value: value, now: ProcessInfo.processInfo.systemUptime) else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    /// A slight tap as a title's menu opens, like a context menu's. Shares the player's rate limit.
    func menu() {
        guard enabled, policy.action(now: ProcessInfo.processInfo.systemUptime) else { return }
        menuImpact.impactOccurred(intensity: 0.6)
        menuImpact.prepare()
    }

    /// A selection tick for a menu's choice or a tab of the bottom bar.
    func select() {
        guard enabled, policy.action(now: ProcessInfo.processInfo.systemUptime) else { return }
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
