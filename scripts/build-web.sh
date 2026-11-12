#!/usr/bin/env bash
# Builds the AIOStreams web app's standalone bundle with the iOS host patch and copies it into
# AIOStreams/Resources/web, where the app serves it from at aiostreams://localhost/.
#
#   scripts/build-web.sh              # the pinned commit below
#   AIOSTREAMS_REF=main scripts/build-web.sh
#
# Needs git, Node 24 and pnpm 11 (corepack enable).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
ref="${AIOSTREAMS_REF:-$(cat "$here/web/AIOSTREAMS_REF")}"
src="$here/build/aiostreams"
out="$here/AIOStreams/Resources/web"

if [ ! -d "$src/.git" ]; then
  git clone --filter=blob:none https://github.com/Viren070/AIOStreams "$src"
fi
git -C "$src" fetch --depth 1 origin "$ref"
git -C "$src" checkout --force FETCH_HEAD
git -C "$src" clean -fdq packages/web/src
# Fail immediately on drift instead of leaving a three-way merge in the build checkout.
git -C "$src" apply --check "$here/web/ios-host.patch"
git -C "$src" apply "$here/web/ios-host.patch"

(
  cd "$src"
  pnpm install --frozen-lockfile --filter "@aiostreams/web..."
  pnpm -F @aiostreams/web build:standalone
)

rm -rf "$out"
mkdir -p "$out"
cp -R "$src/packages/web/dist-standalone/." "$out/"
git -C "$src" rev-parse HEAD > "$out/aiostreams-commit.txt"
echo "patched: ios-host.patch" >> "$out/aiostreams-commit.txt"
echo "web app $(git -C "$src" rev-parse --short HEAD) -> $out"
