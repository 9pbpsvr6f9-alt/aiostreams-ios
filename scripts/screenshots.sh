#!/usr/bin/env bash
# Photographs both apps in Apple's simulators against the demo server (tools/demo-server), whose
# catalogue and artwork are made up, so the pictures show no one's films, servers or accounts.
#
#   scripts/screenshots.sh      # writes build/screenshots/*.png
#
# Needs macOS with Xcode and its iOS and tvOS simulators, XcodeGen, ffmpeg and Pillow, and the web
# app built into AIOStreams/Resources/web (scripts/build-web.sh).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
out="$here/build/screenshots"
derived="$here/build/SimDerivedData"
rm -rf "$out"
mkdir -p "$out"

port=8096
server="http://127.0.0.1:$port/jellyfin"
tools/demo-server/make-video.sh
python3 tools/demo-server/server.py --port "$port" > "$here/build/demo-server.log" 2>&1 &
server_pid=$!
trap 'kill $server_pid 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -sf "$server/System/Info/Public" >/dev/null && break; sleep 1; done

# The demo catalogue's ids, as the server makes them.
id() { python3 -c "import sys; sys.path.insert(0, 'tools/demo-server'); import server; print(server.make_id(*sys.argv[1:]))" "$@"; }
show=$(id show "Signal & Noise")
movie=$(id movie "Northern Lights")
user=$(id user Alex)
server_id=$(python3 -c "import sys; sys.path.insert(0, 'tools/demo-server'); import server; print(server.SERVER_ID)")

xcodegen generate

build() {
  xcodebuild build -project AIOStreams.xcodeproj -scheme "$1" -configuration Debug \
    -destination "generic/platform=$2" -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO | tail -3
}
build AIOStreams "iOS Simulator"
build AIOStreamsTV "tvOS Simulator"
ios_app="$derived/Build/Products/Debug-iphonesimulator/AIOStreams.app"
tv_app="$derived/Build/Products/Debug-appletvsimulator/AIOStreamsTV.app"

# A booted simulator of the newest device whose name matches, on the newest runtime that has it.
simulator() {
  python3 - "$1" "$2" <<'PY'
import json, subprocess, sys
pattern, platform = sys.argv[1], sys.argv[2]
types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", "devicetypes"]))["devicetypes"]
runtimes = [r for r in json.loads(subprocess.check_output(["xcrun", "simctl", "list", "-j", "runtimes"]))["runtimes"]
            if r["isAvailable"] and r["platform"] == platform]
runtime = sorted(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])[-1]
supported = {t["identifier"] for t in runtime.get("supportedDeviceTypes", [])}
matches = [t for t in types if pattern in t["name"] and (not supported or t["identifier"] in supported)]
device = matches[-1]
udid = subprocess.check_output(["xcrun", "simctl", "create", f"Shots {device['name']}", device["identifier"], runtime["identifier"]]).decode().strip()
print(udid)
PY
}

prepare() {
  local udid="$1"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance dark || true
}

shot() {
  local udid="$1" bundle="$2" name="$3" wait="$4"
  shift 4
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl launch "$udid" "$bundle" -demoServer "$server" "$@" >/dev/null
  sleep "$wait"
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null
  echo "captured $name"
}

# Apple TV
tv=$(simulator "Apple TV 4K" tvOS)
prepare "$tv"
xcrun simctl install "$tv" "$tv_app"
tvid=io.github.aiostreams-ios.tv
shot "$tv" $tvid tv-signin 8 -demoScreen signin
shot "$tv" $tvid tv-home 14 -demoScreen home
shot "$tv" $tvid tv-rail 14 -demoScreen rail
shot "$tv" $tvid tv-show 14 -demoScreen title -demoItem "$show"
shot "$tv" $tvid tv-movie 14 -demoScreen movie -demoItem "$movie"
shot "$tv" $tvid tv-versions 14 -demoScreen versions -demoItem "$movie"
shot "$tv" $tvid tv-player 20 -demoScreen player -demoItem "$movie"
shot "$tv" $tvid tv-settings 12 -demoScreen settings
xcrun simctl shutdown "$tv" || true

# iPhone and iPad: the web app, signed in to the demo server.
web() {
  local udid="$1" prefix="$2"
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$udid" "$ios_app"
  local args=(-demoServerId "$server_id" -demoUserId "$user" -demoToken demo-token)
  local appid=io.github.aiostreams-ios.app
  shot "$udid" $appid "$prefix-home" 14 "${args[@]}" -demoRoute "/"
  shot "$udid" $appid "$prefix-show" 14 "${args[@]}" -demoRoute "/item/$show"
  shot "$udid" $appid "$prefix-movie" 14 "${args[@]}" -demoRoute "/item/$movie"
  shot "$udid" $appid "$prefix-versions" 16 "${args[@]}" -demoRoute "/item/$movie?pick=$movie"
  shot "$udid" $appid "$prefix-player" 20 "${args[@]}" -demoRoute "/play/$movie?source=$movie"
}

phone=$(simulator "Pro Max" iOS)
prepare "$phone"
web "$phone" iphone
xcrun simctl shutdown "$phone" || true

ipad=$(simulator "iPad Pro 13" iOS)
prepare "$ipad"
web "$ipad" ipad
xcrun simctl shutdown "$ipad" || true

ls -l "$out"
