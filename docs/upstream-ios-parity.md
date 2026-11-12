# iOS upstream parity update

Sources reviewed: mickey2266/AIOStreamsTVOS at a50eb080cffe1c0e6350964ef2a775478a95de14,
and official Viren070/AIOStreams at the commit in web/AIOSTREAMS_REF.

This update rebases the iOS host onto the official web app's current file layout,
including its upscaling subscription teardown. The build checks patch applicability
without three-way merges and records the bundled source commit.

The native YouTube resolver and bounded subtitle container index reader come from
the reference app. The index supports Matroska cues and MP4/MOV sample tables,
for the web player's subtitle sync. Requests keep the media's HTTP headers, cache
one index per load, and discard results when playback changes. Embedded tracks
must match the index's count and picture/text classification before returning times.
Line subscriptions use this index; decoded-line fallback is not implemented.

The existing SubtitleOverlayView.swift, including the user's main-branch subtitle
changes, is unchanged. The native TV app is unchanged. Private tvOS WebKit, remote
focus patches, Top Shelf and HDMI output behavior do not apply to this iOS shell.
PiP, offline downloads, engine statistics and further engine-setting parity remain
future work; this change does not advertise them as supported.

## Validation

- Shell syntax, git diff whitespace, and clean forward/reverse host patch checks pass.
- Official standalone web production build passes using the installed Rsbuild CLI;
  one optional framer-motion dependency warning remains.
- Frozen dependency install downloads packages but fails the official source's
  minimum release age policy for @aiostreams/webgpu-player@0.4.1. Policy was not changed.
- Web TypeScript check runs but fails on missing @aiostreams/core declarations and
  dependent party types; the filtered installation does not build core declarations.
- Native IPA build cannot run here: Linux has neither XcodeGen nor Xcode/Apple SDKs.
  The existing pull-request macOS Build IPA workflow should validate native code.
- Device checks still required: trailer availability, subtitle sync on actual indexed
  containers, switching files while indexing, and subtitle appearance on iPhone/iPad.
