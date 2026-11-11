# AIOStreams for iOS and Apple TV

An unofficial iPhone, iPad and Apple TV port of the [AIOStreams](https://github.com/Viren070/AIOStreams) app, playing through [AetherEngine](https://github.com/superuser404notfound/AetherEngine).

It follows the design of the official Android and desktop apps, which are a web view over a native player. Their source is public under AGPL-3.0, so this port builds from that source rather than from the APK.

- The page is AIOStreams' own web app (`packages/web`, standalone build). It draws every screen and the player's controls.
- The page talks to the app through `window.aiostreamsApp`, the same bridge (protocol 2) the Android and desktop apps use. The page itself is almost unchanged: `web/ios-host.patch` adds one small host (`platform: 'ios'`) so the page knows it's on iOS.
- The video is drawn by AetherEngine beneath a transparent `WKWebView`. AetherEngine replaces mpv and ExoPlayer and brings FFmpeg demuxing, VideoToolbox and dav1d decoding, HDR10, HDR10+, Dolby Vision and HLG, and Atmos.
- The engine leaves subtitle drawing to the app. A native layer between the video and the page draws them, in the style chosen in the page's subtitle settings.

```
┌──────────────────────────────┐
│ WKWebView (transparent)      │  aiostreams://localhost/  ← bundled web app
│   window.aiostreamsApp  ⇅    │  JSON messages: player-load, player-state, …
├──────────────────────────────┤
│ SubtitleOverlayView          │  engine.subtitleCues @ clock.sourceTime
├──────────────────────────────┤
│ AetherPlayerView             │  AetherEngine
└──────────────────────────────┘
```

## Getting an IPA

You need macOS to build it; this repository has no prebuilt binary. Either:

**GitHub Actions (no Mac needed).** Push this repository to GitHub. The `Build IPA` workflow runs on a `macos-26` runner and uploads `AIOStreams.ipa` as a workflow artifact. Pushing a `v*` tag also attaches it to a release.

**Locally on a Mac** with Xcode 27 (26.3 is AetherEngine's best-effort floor), Node 24, pnpm 11 and XcodeGen:

```bash
brew install xcodegen
```

```bash
scripts/make-ipa.sh
```

The IPA is unsigned. Sign it when you install it with AltStore, SideStore, Sideloadly, or your own developer certificate. With a free Apple ID, apps expire after 7 days and must be refreshed.

To run it from Xcode instead, run `scripts/build-web.sh`, then `xcodegen generate`, open `AIOStreams.xcodeproj`, choose your team under Signing, and run it on a device.

## What maps to what

| Page message | iOS app |
| --- | --- |
| `player-load` (url, headers, start, languages) | `engine.load(url:startPosition:options:)` with `httpHeaders`, `isLive`, preferred languages |
| `player-set` (paused, volume, speed, audio, subtitle, delay) | `play`/`pause`, `volume`, `setRate`, `selectAudioTrack`, `selectSubtitleTrack`/`clearSubtitle`, overlay delay |
| `player-seek` | `engine.seek(to:exact:)` |
| `player-subtitle-add`, `subtitle-file` | `addExternalSubtitleTrack` |
| `player-style` (fit, subtitle look) | `videoGravity`, the overlay's style |
| `player-thumbnail` | `scrubThumbnail(atSeconds:)`, served at `/thumbnail/…` |
| `now-playing`, `media-key` | Now Playing info and lock screen controls |
| `fullscreen` | landscape, no status bar or home indicator |
| `player-state` / `player-tracks` / `player-chapters` / `player-event` / `player-ended` | the engine's published state |

## Apple TV

tvOS has no WebKit, so the web app can't run there. The Apple TV app (`TV/`) is native SwiftUI instead. It talks to the server's Jellyfin API with the same requests the web app makes (`packages/web/src/lib/queries.ts`), and plays with the same AetherEngine. The engine handles the HDR and Dolby Vision display switching itself, following the Apple TV's Match Content setting.

- **Connecting:** enter the server address from the configure page (Save & Install → Jellyfin apps → Connect). Sign in with Quick Connect (approve the code on the configure page), by picking a user, or with a name and password.
- **Browsing:** Home has Continue Watching, Next Up and a row for each library. There's also search, library grids, and details pages with seasons and episodes.
- **Versions:** the streams your addons found, in the order the server sorted them. Picking one also fetches its subtitles from your subtitle addons.
- **Player:** play/pause, click left or right to go back 10 s or forward 30 s, and press down for audio and subtitles. Playback resumes where you left off and reports progress to the server.

It shares `Support.swift` and `SubtitleOverlayView.swift` with the iOS app. The build makes `AIOStreams-tvOS.ipa` alongside the iPhone one. AltStore and SideStore don't install on Apple TV. Use Xcode with a paired Apple TV, or another signing tool that supports tvOS.

Not in the Apple TV app yet: scrubbing with the touch surface, playing the next episode automatically, skipping intros, Live TV, and a subtitle style setting.

## Not done yet

- **Downloads and offline playback.** The iOS host has no `downloads`, so the page hides them.
- **Mini player and picture-in-picture.** The bridge reports `miniPlayer: false`.
- **Stats overlay.** mpv's stats pages have no AetherEngine equivalent here.
- **Subtitle line index.** It feeds the page's subtitle sync tools; the app answers that it has none.
- **YouTube trailers.** `youtube-resolve` answers with no stream.
- **Desktop-only settings.** Cards such as mpv config, video output and audio devices may still show; the app answers each with an empty list.

## Updating

`web/AIOSTREAMS_REF` pins the AIOStreams commit the web app is built from, so the patch applies cleanly. To move to a newer one, change it and check that `git apply` of `web/ios-host.patch` still succeeds. If it doesn't, regenerate the patch. `project.yml` pins AetherEngine to an exact version.

## Optional AetherEngine components

Both apps build AetherEngine through `Packages/AetherEngineFeatures`, which turns on three of its optional components (XcodeGen can't set a package's traits itself):

- **TrueHD Atmos and DTS:X height channels** (`TrueHDObjectAudio`, `DTSXObjectAudio`). The apps ask the engine to render them for 7.1.4 speakers. On Apple TV the layout is a setting (Settings → Audio), and the result reaches an Atmos receiver as Dolby MAT. iPhone and iPad play it as Spatial Audio. Needs iOS or tvOS 26. Otherwise they play as their 7.1 channels.
- **Dolby Vision Profile 7 FEL, by curve fold only** (`DolbyVisionFelCurves`): the enhancement layer is folded into the Profile 8.1 picture on Apple's own video path, which applies it with its licensed decoder. The engine's software dual-layer composer (`DualLayerDolbyVision`), whose steps are covered by Dolby patents, is deliberately left off.

AetherEngine notes that these components may be subject to third-party patent licensing, which is the responsibility of whoever builds and distributes the app with them.

## Licence

AGPL-3.0, like AIOStreams (`LICENSE`). AetherEngine is LGPL-3.0 with an App Store exception, and is linked statically from its tagged release. FFmpeg is LGPL-2.1+ and is embedded as dynamic frameworks. The app's licences screen lists both.

This is an unofficial port, not affiliated with AIOStreams or AetherEngine.
