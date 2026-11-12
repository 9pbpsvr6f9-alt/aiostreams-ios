// Runs against the production helper in the Mac workflow, without UIKit or engine dependencies.
let cases: [(Double, Double, Double)] = [
    (0.3, 0.5, 0.15), // Phone at 30%, page at 50%: hand off at 15%, not 30%.
    (0.3, 1, 0.3),    // No attenuation: leave the system level alone.
    (0.3, 0, 0),      // Muted/zero player gain: hand off at silence.
    (0, 0.8, 0),
    (1, 1, 1),
    (-0.1, 0.5, 0),
    (0.5, 2, 0.5),    // The engine clamps player volume to unity too.
]
for (system, player, expected) in cases {
    guard let actual = SwipeVolume.start(system: system, player: player) else {
        fatalError("Valid volume pair was rejected")
    }
    precondition(abs(actual - expected) < 0.000001, "Unexpected normalized start level")
}
precondition(SwipeVolume.start(system: .nan, player: 1) == nil)
precondition(SwipeVolume.start(system: 0.3, player: .infinity) == nil)
print("Swipe volume normalization tests passed")
