#!/bin/bash
# SUZURI フラット缶ケース用の入稿データ。plain.html の can(パーツと空きソケットの 4x4 格子と、その下の文字ロゴ。吹き出しも記号もなし)を、
# 地もドットもなしの透過で、テンプレート(suzuri-template-flat-can-case、1418x1773px)の赤線の枠に収めて置く。
#   ./can-case.sh  → out/can-case-c.png(入稿データ)、out/can-case-c-preview.png(テンプレートを重ねた確認用)
# 要: Google Chrome、ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TPL=../../suzuri-template-flat-can-case/flat-can-case.png
CW=1418; CH=1773           # テンプレートの大きさ
RX0=115; RY0=100; RX1=1302; RY1=1672   # 赤線(切れてほしくないものを収める枠)
WIDTH=1150                 # 切り出し(CSS 600px 幅)の横幅。パーツは c の 0.85 倍、格子の外幅は約 830px
mkdir -p out

# can を地なし・透過で原寸(x5)で撮り、格子と文字ロゴの中心(CSS x 753 / y 673)より 6px 上を中心にした範囲(x ±300 / y ±370)を切り出す(小さい 2026 Assemble の下が空いて見えるので、少し下に寄せる)
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=5 --window-size=1507,1177 \
  --default-background-color=00000000 --virtual-time-budget=30000 --screenshot=out/tmp_can.png \
  "file://$PWD/plain.html?capture=can-front-light&nodots=1" 2>/dev/null
magick out/tmp_can.png -crop 3000x3700+2265+1487 +repage -resize "${WIDTH}x" out/tmp_grid.png
# 赤線の枠の中央に置く(キャンバスは sRGB にしておく。xc:none のままだとグレースケールになる)
magick -size "${CW}x${CH}" xc:none -colorspace sRGB -type TrueColorAlpha out/tmp_grid.png -gravity NorthWest \
  -geometry "+$(( (RX0 + RX1) / 2 - $(magick identify -format '%w' out/tmp_grid.png) / 2 ))+$(( (RY0 + RY1) / 2 - $(magick identify -format '%h' out/tmp_grid.png) / 2 ))" \
  -composite out/can-case-c.png
# 確認用: テンプレートの説明文(矩形)と赤線を白で消してから、入稿データを重ねる
magick "$TPL" -background white -alpha remove -fill white -draw "rectangle 250,800 1170,960" \
  -fx "(r > g + 0.12 && r > b + 0.12) ? 1 : u" \
  out/can-case-c.png -composite out/can-case-c-preview.png
command rm -f out/tmp_can.png out/tmp_grid.png
magick identify -format "%f %wx%h\n" out/can-case-c.png
