#!/bin/bash
# Goodies ページの Official Goods のアイキャッチ。plain.html の c(パーツの 4x3 格子)を、記号・吹き出し・文字ロゴなし(?parts=1)で
# ドットの地ごと撮り、格子の左右に 100px・上下に 50px(CSS)の余白を取って横長に切り出す。
#   ./eyecatch.sh  → ../../images/goodies/official-goods.png(幅 800px、ディザなしの 256 色)
# 要: Google Chrome、ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT=../../images/goodies/official-goods.png
MARGIN_X=500   # 原寸(x5)での左右の余白 = CSS 100px
MARGIN_Y=250   # 上下の余白 = CSS 50px
mkdir -p out

# 格子の範囲は、地なし(透過)で撮ったものの不透明な部分から取る
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=5 --window-size=1507,1177 \
  --default-background-color=00000000 --virtual-time-budget=30000 --screenshot=out/tmp_parts_alpha.png \
  "file://$PWD/plain.html?capture=c-front-light&nodots=1&parts=1" 2>/dev/null
BBOX=$(magick out/tmp_parts_alpha.png -format '%@' info:)   # 例 2233x1587+2632+2005
W=${BBOX%%x*}; BBOX=${BBOX#*x}; H=${BBOX%%+*}; BBOX=${BBOX#*+}; X=${BBOX%%+*}; Y=${BBOX#*+}

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=5 --window-size=1507,1177 \
  --virtual-time-budget=30000 --screenshot=out/tmp_parts.png \
  "file://$PWD/plain.html?capture=c-front-light&parts=1" 2>/dev/null
magick out/tmp_parts.png -crop "$((W + 2 * MARGIN_X))x$((H + 2 * MARGIN_Y))+$((X - MARGIN_X))+$((Y - MARGIN_Y))" +repage \
  -resize 800x -dither None -colors 256 "PNG8:$OUT"
command rm -f out/tmp_parts_alpha.png out/tmp_parts.png
magick identify -format "%f %wx%h\n" "$OUT"
