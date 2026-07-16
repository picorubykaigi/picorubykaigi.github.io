#!/bin/bash
# ショップカード入稿データのビルド
# index.html を600dpi相当でキャプチャして front.png / back.png / shopcard.pdf を作る。
# HTML/CSSのままPDF化すると繰り返しSVG背景やtext-shadowの描画がビューア/RIP依存になるため、
# 入稿データはラスタ(600dpi)で固める。
# 要: Google Chrome, ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# 61x97mm(塗り足し3mm込み) = CSS 230.6x366.6px。600dpiで1441x2291px
CSS_W=231
CSS_H=367
SCALE=6.25
PX_W=1441
PX_H=2291

for side in front back; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=$SCALE --window-size=$CSS_W,$CSS_H \
    --virtual-time-budget=20000 \
    --screenshot="$side.png" "file://$PWD/index.html?capture=$side"
  magick "$side.png" -crop "${PX_W}x${PX_H}+0+0" +repage \
    -density 600 -units PixelsPerInch "$side.png"
done

magick front.png back.png -density 600 -units PixelsPerInch shopcard.pdf
echo "done: front.png back.png shopcard.pdf (61x97mm, 塗り足し3mm込み)"
