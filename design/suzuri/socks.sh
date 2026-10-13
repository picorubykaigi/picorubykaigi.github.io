#!/bin/bash
# SUZURI ソックス用の入稿データ。plain.html の socks(缶ケースの can と同じ 4x4 の格子と文字ロゴ。列と行の間隔を詰めてある)を、
# 地もドットもなしの透過で、足の甲に収まる大きさで展開図のつま先側に置く。
# テンプレート(suzuri-template-socks、25-27cm の 1731x4094px。赤線の枠は y 80-3784。かかとは y 2084-2803 の帯で、
# 左右の端から x 482 / 1248 まで切れ込み、帯の上下 115px は x 311 / 1419 まで。左右の辺は脚では背面、かかとより下では足裏で接合される)。
# 配置: 文字ロゴの下端をつま先の赤線の 20px 上に置き、格子の上端がかかとの帯の中心あたりに来る大きさ(CSS の 1.9 倍。格子の外幅 676px で
# かかとの切れ込みの内側 766px に収まり、パーツは約 1.2cm)。
# 入稿データは幅だけテンプレートに合わせ、何もない脚の部分はかかとの帯の上端(y 2084)で切り落とす(1731x2010px)。
#   ./socks.sh  → out/socks.png(入稿データ)、preview/socks-preview.png(展開図全体にテンプレートを重ねた確認用、長辺 1600px 以内・256 色)
# 要: Google Chrome、ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TPL=templates/suzuri-template-socks/socks.png
CW=1731; CH=4094           # テンプレートの大きさ
CUT=2084                   # 入稿データはここから下
SCALE=1.9
mkdir -p out preview

# socks を地なし・透過で x1.9 で撮り、格子と文字ロゴの範囲(CSS x 453-1053 / y 297-1037)を切り出す。文字ロゴの下端は切り出しの上端から CSS 685px
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=$SCALE --window-size=1507,1177 \
  --default-background-color=00000000 --virtual-time-budget=30000 --screenshot=out/tmp_socks.png \
  "file://$PWD/plain.html?capture=socks-front-light&nodots=1" 2>/dev/null
magick out/tmp_socks.png -crop 1140x1406+861+564 +repage out/tmp_grid.png
# 展開図全体に置く(キャンバスは sRGB にしておく。xc:none のままだとグレースケールになる)。文字ロゴの下端を赤線の 20px 上に
magick -size "${CW}x${CH}" xc:none -colorspace sRGB -type TrueColorAlpha out/tmp_grid.png -gravity NorthWest \
  -geometry "+$(( 865 - 1140 / 2 ))+$(( CH - 310 - 20 - 1301 ))" -composite out/tmp_full.png
magick out/tmp_full.png -crop "${CW}x$(( CH - CUT ))+0+${CUT}" +repage out/socks.png
# 確認用: テンプレート(赤線とかかと・履き口・つま先の文字)に展開図全体を重ねる
magick "$TPL" out/tmp_full.png -composite -resize '1600x1600>' -dither None -colors 256 PNG8:preview/socks-preview.png
command rm -f out/tmp_socks.png out/tmp_grid.png out/tmp_full.png
magick identify -format "%f %wx%h\n" out/socks.png
