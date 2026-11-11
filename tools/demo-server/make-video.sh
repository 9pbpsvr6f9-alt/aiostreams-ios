#!/usr/bin/env bash
# Makes the demo server's video: a slow push into one of its own generated landscapes, with a quiet
# tone for sound, so the player has something to show that isn't anyone's film.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
python3 - "$here" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import art, server
palette = server.PALETTES["aurora"]
art.backdrop(palette, 3, True, 2560, 1440).save(f"{sys.argv[1]}/frame.png")
PY
ffmpeg -y -loglevel error -loop 1 -i "$here/frame.png" \
  -f lavfi -i "sine=frequency=220:sample_rate=48000" \
  -filter_complex "[0:v]scale=2560:1440,zoompan=z='1+0.0006*on':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1920x1080:fps=24,format=yuv420p[v];[1:a]volume=0.05[a]" \
  -map "[v]" -map "[a]" -t 60 -c:v libx264 -profile:v high -preset veryfast -crf 26 -c:a aac -b:a 96k \
  -movflags +faststart "$here/demo.mp4"
rm -f "$here/frame.png"
ls -l "$here/demo.mp4"
