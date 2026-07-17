#!/bin/zsh
# Renders tools/ogp_game.html (GC PANIC card) to images/ogp_game.png.
# Same approach as render_ogp.sh: screenshot at device-scale-factor=2
# (2400x1260) with no downscaling, so the pixel art stays crisp.
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=8765
SCALE=2

if ! curl -s -o /dev/null "http://localhost:$PORT/tools/ogp_game.html"; then
  (python3 -m http.server $PORT >/tmp/ogp_srv.log 2>&1 &)
  sleep 1
fi

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=$SCALE --window-size=1200,630 \
  --virtual-time-budget=12000 \
  --screenshot="images/ogp_game.png" "http://localhost:$PORT/tools/ogp_game.html" 2>/dev/null

magick identify -format "OGP game: %wx%h\n" images/ogp_game.png
