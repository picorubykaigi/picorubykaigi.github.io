#!/bin/zsh
# Render each slide of index.html to out/<name>.png (1920x1080) with headless Chrome.
set -e
cd "$(dirname "$0")/../.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=8767
PAGE="http://localhost:$PORT/design/keynote-template/index.html"
OUT=design/keynote-template/out
CACHE_BUST="$(date +%s)$$"
mkdir -p "$OUT"

if ! curl -s -o /dev/null "$PAGE"; then
  (python3 -m http.server $PORT >/dev/null 2>&1 &)
  sleep 1
fi

names=(${(f)"$(grep -o 'data-name="[^"]*"' design/keynote-template/index.html | cut -d'"' -f2)"})
for name in ${@:-$names}; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --window-size=1920,1080 --virtual-time-budget=8000 \
    --screenshot="$OUT/$name.png" "$PAGE?only=$name&cb=$CACHE_BUST" 2>/dev/null
done
ls "$OUT"
