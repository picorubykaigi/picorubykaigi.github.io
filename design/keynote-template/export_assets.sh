#!/bin/zsh
# Render the pieces the Keynote template is assembled from into out/keynote/:
#   <slide>-background.png  decoration only (no editable text, no logo), 2x
#   logo-lockup.png         title slide logo (Ruby + PicoRubyKaigi), transparent, 2x
#   logo-footer.png         footer logo of the body slides, transparent, 2x
#   bullet-1.png / bullet-2.png  list markers, transparent
#   layout.json             position of each element in 1920x1080 px
set -e
cd "$(dirname "$0")/../.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=8767
PAGE="http://localhost:$PORT/design/keynote-template/index.html"
OUT=design/keynote-template/out/keynote
CACHE_BUST="$(date +%s)$$"
mkdir -p "$OUT"

if ! curl -s -o /dev/null "$PAGE"; then
  (python3 -m http.server $PORT >/dev/null 2>&1 &)
  sleep 1
fi

shoot() {  # shoot <query> <out.png> [extra chrome flags...]
  local query=$1 out=$2
  shift 2
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --window-size=1920,1080 --force-device-scale-factor=2 --virtual-time-budget=8000 "$@" \
    --screenshot="$out" "$PAGE?$query&cb=$CACHE_BUST" 2>/dev/null
}

"$CHROME" --headless=new --disable-gpu --window-size=1920,1080 --virtual-time-budget=8000 \
  --dump-dom "$PAGE?measure=1&only=01-title&cb=$CACHE_BUST" 2>/dev/null | sed -n 's/.*<pre id="measure">\(.*\)<\/pre>.*/\1/p' > "$OUT/layout-title.json"
names=(${(f)"$(grep -o 'data-name="[^"]*"' design/keynote-template/index.html | cut -d'"' -f2)"})
for name in $names; do
  "$CHROME" --headless=new --disable-gpu --window-size=1920,1080 --virtual-time-budget=8000 \
    --dump-dom "$PAGE?measure=1&only=$name&cb=$CACHE_BUST" 2>/dev/null | sed -n 's/.*<pre id="measure">\(.*\)<\/pre>.*/\1/p' > "$OUT/layout-$name.json"
  shoot "only=$name&mode=background" "$OUT/$name-background.png"
done
command rm -f "$OUT/layout-title.json"

shoot "only=01-title&mode=logo" "$OUT/logo-lockup.png" --default-background-color=00000000
shoot "only=02-about-me&mode=logo" "$OUT/logo-footer.png" --default-background-color=00000000
shoot "only=02-about-me&mode=frame" "$OUT/photo-frame.png" --default-background-color=00000000
magick "$OUT/photo-frame.png" -trim +repage "$OUT/photo-frame.png"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=400,400 --force-device-scale-factor=4 \
  --default-background-color=00000000 --virtual-time-budget=4000 \
  --screenshot="$OUT/bullets.png" "http://localhost:$PORT/design/keynote-template/bullets.html?cb=$CACHE_BUST" 2>/dev/null
# Keynote sits image bullets higher than the CSS marker; transparent space on top pulls the square down.
magick "$OUT/bullets.png" -crop 1100x800+0+0 +repage -trim +repage \
  -background none -gravity south -extent "%[fx:w]x%[fx:round(h*1.03)]" "$OUT/bullet-1.png"
magick "$OUT/bullets.png" -crop 1100x800+0+800 +repage -trim +repage "$OUT/bullet-2.png"
# Keynote leaves hairline gaps where tiles meet, so the tile covers the whole code panel at 2x.
magick "$OUT/bullets.png" -crop 256x256+1184+224 +repage -resize 50% "$OUT/code-tile.png"
magick -size 3440x1500 "tile:$OUT/code-tile.png" "$OUT/code-tile.png"
command rm -f "$OUT/bullets.png"

for logo in lockup footer; do
  magick "$OUT/logo-$logo.png" -format "%@" info: > "$OUT/logo-$logo.geometry"
  magick "$OUT/logo-$logo.png" -trim +repage "$OUT/logo-$logo.png"
done

pkill -f "http.server $PORT" || true
ls "$OUT"
