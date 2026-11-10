#!/usr/bin/env bash
# Builds an unsigned AIOStreams.ipa on macOS, for signing at install time
# (AltStore, SideStore, Sideloadly, or your own certificate).
#
#   scripts/make-ipa.sh   # writes build/AIOStreams.ipa
#
# Needs Xcode 27 (AetherEngine's supported toolchain; 26.3 is best effort) and XcodeGen.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"

[ -f AIOStreams/Resources/web/index.html ] || scripts/build-web.sh
xcodegen generate

derived="$here/build/DerivedData"
xcodebuild build \
  -project AIOStreams.xcodeproj \
  -scheme AIOStreams \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

app="$derived/Build/Products/Release-iphoneos/AIOStreams.app"
[ -d "$app" ] || { echo "no app at $app" >&2; exit 1; }

staging="$here/build/ipa"
rm -rf "$staging"
mkdir -p "$staging/Payload"
cp -R "$app" "$staging/Payload/"
(cd "$staging" && zip -qry "$here/build/AIOStreams.ipa" Payload)
echo "built $here/build/AIOStreams.ipa"
