#!/usr/bin/env bash
# Builds unsigned IPAs on macOS, for signing at install time:
#   build/AIOStreams.ipa        iPhone and iPad (AltStore, SideStore, Sideloadly, or your own certificate)
#   build/AIOStreams-tvOS.ipa   Apple TV (Xcode, or a signing tool that supports tvOS)
#
#   scripts/make-ipa.sh            # both
#   scripts/make-ipa.sh ios        # one of them
#   scripts/make-ipa.sh tvos
#   HEIGHT_CHANNELS=on scripts/make-ipa.sh   # with TrueHD Atmos and DTS:X height channels
#
# Height channels are off unless asked for: AetherEngine notes they may be subject to third-party
# patent licensing, so public releases leave them out. Dolby Vision FEL (curve fold) is in both.
#
# Needs Xcode 27 (AetherEngine's supported toolchain; 26.3 is best effort) and XcodeGen.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
which="${1:-all}"

# The engine package to build with: the same module, with or without height channels.
if [ "${HEIGHT_CHANNELS:-off}" = on ]; then
  engine=AetherEngineHeights
  echo "building with height channels"
else
  engine=AetherEngineFeatures
fi
sed "s#path: Packages/AetherEngineFeatures#path: Packages/$engine#" project.yml > project.gen.yml
xcodegen generate --spec project.gen.yml
rm -f project.gen.yml
derived="$here/build/DerivedData"

build() {
  local scheme="$1" platform="$2" products="$3" ipa="$4"
  xcodebuild build \
    -project AIOStreams.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination "generic/platform=$platform" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

  local app="$derived/Build/Products/$products/$scheme.app"
  [ -d "$app" ] || { echo "no app at $app" >&2; exit 1; }
  local staging="$here/build/ipa-$scheme"
  rm -rf "$staging" "$here/build/$ipa"
  mkdir -p "$staging/Payload"
  cp -R "$app" "$staging/Payload/"
  (cd "$staging" && zip -qry "$here/build/$ipa" Payload)
  echo "built $here/build/$ipa"
}

if [ "$which" = all ] || [ "$which" = ios ]; then
  [ -f AIOStreams/Resources/web/index.html ] || scripts/build-web.sh
  build AIOStreams iOS Release-iphoneos AIOStreams.ipa
fi
if [ "$which" = all ] || [ "$which" = tvos ]; then
  build AIOStreamsTV tvOS Release-appletvos AIOStreams-tvOS.ipa
fi
