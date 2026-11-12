/// Preserve the existing effective level when moving attenuation from the player to the system.
enum SwipeVolume {
    static func start(system: Double, player: Double) -> Double? {
        guard system.isFinite, player.isFinite else { return nil }
        return min(max(system, 0), 1) * min(max(player, 0), 1)
    }
}
