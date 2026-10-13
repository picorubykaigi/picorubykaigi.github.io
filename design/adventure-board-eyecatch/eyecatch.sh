#!/bin/bash
# Adventure Board のアイキャッチ。board-photo.jpg(白背景の基板写真)から基板を切り抜き、基板の緑だけ PCB らしい黄緑寄りに
# 寄せてから、eyecatch.html(styles.css のロゴ+Jersey 10 の名前)を 1200x630 の 2 倍で撮る。
#   ./eyecatch.sh  → adventure-board-eyecatch.jpg(2400x1260)
# 要: Google Chrome、ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT=adventure-board-eyecatch.jpg
mkdir -p out

# 白背景を四隅と、基板の切り欠き・脇から塗りつぶし、残った不透明部分を基板のマスクにする。
# 全体は fuzz 12%(基板の縁の影まで落ちる)で抜き、12% では欠ける 2 つの GROVE コネクタの範囲だけ 7% のマスクを使う。
# 縁は白→緑のグラデーション(15px ほど)の途中に灰色が残るので、Erode で緑に入るところまで内側に寄せ、ぼかしてなめらかにする
board_mask() {  # board_mask <fuzz> <out.png>
  magick board-photo.jpg -alpha set -fuzz "$1" -fill none \
    -draw "color 0,0 floodfill" -draw "color 2401,0 floodfill" -draw "color 0,3393 floodfill" -draw "color 2401,3393 floodfill" \
    -draw "color 1217,2762 floodfill" -draw "color 1217,40 floodfill" -draw "color 1217,3350 floodfill" \
    -alpha extract "$2"
}
board_mask 12% out/mask_wide.png
board_mask 7% out/mask_narrow.png
magick out/mask_narrow.png \
  \( -size 2402x3394 xc:black -fill white -draw "rectangle 297,482 657,862" -draw "rectangle 57,2062 477,2462" \) \
  -compose multiply -composite out/mask_wide.png -compose lighten -composite \
  -morphology Open Disk:4 -morphology Erode Disk:14 -blur 0x2 out/mask_board.png
magick board-photo.jpg out/mask_board.png -alpha off -compose CopyOpacity -composite -trim +repage out/board.png

# 色相が緑(HSL の 30%〜58%)の部分だけのマスク(赤いブレッドボードと白いコネクタは外れる)。透過部分は基板の alpha で切る
magick out/board.png -alpha off -colorspace HSL -channel R -separate +channel \
  \( -clone 0 -threshold 30% \) \( -clone 0 -threshold 58% -negate \) -delete 0 \
  -compose multiply -composite -morphology Close Disk:2 \
  \( out/board.png -alpha extract \) -compose multiply -composite out/mask_green.png

# -modulate 明度,彩度,色相。色相は 100 が変化なしで、小さくすると黄緑へ回る
magick out/board.png \( +clone -modulate 104,140,90 \) out/mask_green.png -composite out/board.png

"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1200,630 \
  --virtual-time-budget=15000 --screenshot=out/eyecatch.png "file://$PWD/eyecatch.html" 2>/dev/null
magick out/eyecatch.png -quality 75 "$OUT"
command rm -f out/mask_wide.png out/mask_narrow.png out/mask_board.png out/mask_green.png out/eyecatch.png
magick identify -format "%f %wx%h\n" "$OUT"
