/// Eligibility is separate from AVKit so previews, pauses and transient interruptions are testable.
struct PictureInPicturePolicy {
    var supported: Bool
    var hasMedia: Bool
    var preview: Bool
    var playing: Bool
    var sourceAvailable: Bool
    var automaticEnabled: Bool

    var prepares: Bool { supported && hasMedia && !preview && sourceAvailable }
    var automatic: Bool { prepares && playing && automaticEnabled }
    static func pausesWhenStopped(wasActive: Bool, restoring: Bool) -> Bool { wasActive && !restoring }
}
