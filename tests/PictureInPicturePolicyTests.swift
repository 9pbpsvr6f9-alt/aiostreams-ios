var policy = PictureInPicturePolicy(supported: true, hasMedia: true, preview: false,
                                    playing: true, sourceAvailable: true, automaticEnabled: true)
precondition(policy.automatic && policy.prepares)
precondition(!policy.shouldStartInBackground(false), "An alert or notification shade alone is not an app switch")
precondition(policy.shouldStartInBackground(true), "Home or opening another app should start eligible PiP")
policy.preview = true
precondition(!policy.prepares && !policy.automatic, "Autoplay artwork must never launch PiP")
policy.preview = false; policy.playing = false
precondition(policy.prepares && !policy.automatic, "Paused video may enter manually but must not auto-start")
policy.playing = true; policy.automaticEnabled = false
precondition(policy.prepares && !policy.automatic, "The automatic toggle must preserve manual PiP")
policy.automaticEnabled = true; policy.sourceAvailable = false
precondition(!policy.prepares, "Unsupported video routes cannot create a blank floating window")
policy.sourceAvailable = true; policy.hasMedia = false
precondition(!policy.prepares)
precondition(PictureInPicturePolicy.pausesWhenStopped(wasActive: true, restoring: false))
precondition(!PictureInPicturePolicy.pausesWhenStopped(wasActive: true, restoring: true))
precondition(!PictureInPicturePolicy.pausesWhenStopped(wasActive: false, restoring: false))
print("Picture in Picture automatic-start and restore policy tests passed")
