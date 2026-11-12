/// Five-percent detents and a short time gate prevent a continuous swipe from buzzing.
struct PlayerHapticPolicy {
    private var buckets: [String: Int] = [:]
    private var lastPulse = -Double.infinity

    mutating func begin(_ level: String, value: Double) {
        guard value.isFinite else { return }
        buckets[level] = Int((min(max(value, 0), 1) * 20).rounded())
    }

    mutating func tick(_ level: String, value: Double, now: Double) -> Bool {
        guard value.isFinite, now.isFinite else { return false }
        let bucket = Int((min(max(value, 0), 1) * 20).rounded())
        guard let before = buckets[level] else { begin(level, value: value); return false }
        guard bucket != before, now - lastPulse >= 0.09 else { return false }
        buckets[level] = bucket
        lastPulse = now
        return true
    }

    mutating func action(now: Double) -> Bool {
        guard now.isFinite, now - lastPulse >= 0.09 else { return false }
        lastPulse = now
        return true
    }
}
