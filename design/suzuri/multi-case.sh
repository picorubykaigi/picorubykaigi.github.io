#!/bin/bash
# SUZURI クリアマルチケース用の入稿データ。板の左右を背面へ折り返し、左右のホックを背面の中央で留める。
# 上下のタブは端を閉じる。地もドットもなしの透過で、正面に Ruby とその下に c のパーツ 3 列 x 4 行、
# 左の折り返し(折ったとき外側=背面に見える)に文字ロゴ(1 行目 PicoRubyKaigi、2 行目 2026 Assemble)を 90 度回して置き、
# 右の折り返しには、折って重ねたときそのロゴの左に来る位置にきらきらを置く。
#   ./multi-case.sh       → out/multi-case.png(通常、テンプレート suzuri-template-clear-multi-case 3545x4465px)
#   ./multi-case.sh mini  → out/mini-multi-case.png(ミニ、suzuri-template-mini-clear-multi-case 2735x3118px。正面が狭いので Ruby なし)
#   いずれも preview/<名前>-preview.png(テンプレートの線を重ねた確認用、長辺 1600px 以内・256 色)も作る
# 要: Google Chrome、ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p out preview

case "${1:-}" in
  mini)
    # ホックの穴は x 342 / 2393、y 1045 / 2066(環の半径は左 88、右 58)。右上(1955, 836)にストラップ用のリング。折り目は x 855 / 1880
    TPL=templates/suzuri-template-mini-clear-multi-case/mini-clear-multi-case.png; NAME=mini-multi-case
    CW=2735; CH=3118; FRONT_X=1367; FLAP_X=506; BODY_Y=1556; KIRA_X=2556
    GRID_W=810; RUBY_W=0; GAP=0; LIFT=0; LOGO_L=900 ;;   # ロゴはホックの環(x 254-430)の右に置く。ミニは正面が狭いので Ruby なし(格子だけを上下中央に)
  *)
    # ホックの穴は x 443 / 3102、y 1223 / 3242(環の半径 93)。折り目は x 1107 / 2437(正面は幅 1330)
    TPL=templates/suzuri-template-clear-multi-case/clear-multi-case.png; NAME=multi-case
    CW=3545; CH=4465; FRONT_X=1772; FLAP_X=627; BODY_Y=2222; KIRA_X=3287
    GRID_W=1050; RUBY_W=380; GAP=110; LIFT=150; LOGO_L=1500 ;;
esac

shot() {  # shot <出力> <面>: 地なし・透過で原寸(x5)に撮る
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=5 --window-size=1507,1177 \
    --default-background-color=00000000 --virtual-time-budget=30000 --screenshot="$1" \
    "file://$PWD/plain.html?capture=$2&nodots=1" 2>/dev/null
}

# 正面: Ruby(c の裏の襟下 Ruby)を上に、その下に c のパーツ 3 列 x 4 行(case-front、吹き出しなし。CSS x 560-960 / y 350-850)
shot out/tmp_front.png case-front-light
magick out/tmp_front.png -crop 2300x3100+2700+1400 +repage -trim +repage -resize "${GRID_W}x" out/tmp_grid.png
if [ "$RUBY_W" -gt 0 ]; then
  shot out/tmp_ruby.png c-back-light
  magick out/tmp_ruby.png -crop 900x700+3300+1250 +repage -trim +repage -resize "${RUBY_W}x" out/tmp_ruby.png
fi
# 背面(左の折り返し): 1 行ロゴ + 2026 Assemble(case-logo、CSS x 480-1030 / y 780-900)。
# 時計回りに 90 度回す(文字の上が折り目側 = 背面から見て右を向き、上から下へ読む)
shot out/tmp_flap.png case-logo-light
magick out/tmp_flap.png -crop 2750x700+2400+3880 +repage -trim +repage -resize "${LOGO_L}x" -rotate 90 out/tmp_logo.png

place() {  # place <入力> <中心x> <中心y> <出力(入出力兼用のキャンバス)>
  local w h; w=$(magick identify -format '%w' "$1"); h=$(magick identify -format '%h' "$1")
  magick "$4" -colorspace sRGB -type TrueColorAlpha "$1" -gravity NorthWest -geometry "+$(( $2 - w / 2 ))+$(( $3 - h / 2 ))" -composite -define png:color-type=6 "$4"
}
magick -size "${CW}x${CH}" xc:none -define png:color-type=6 "out/$NAME.png"  # RGBA で書く(xc:none のままだとグレースケールになる)
# 格子は Ruby と合わせてボディの上下中央に置いた位置のまま、Ruby だけ LIFT ぶん上げる
GH=$(magick identify -format '%h' out/tmp_grid.png)
RH=0; [ "$RUBY_W" -gt 0 ] && RH=$(magick identify -format '%h' out/tmp_ruby.png)
TOP=$(( BODY_Y - (RH + GAP + GH) / 2 ))
[ "$RUBY_W" -gt 0 ] && place out/tmp_ruby.png $FRONT_X $(( TOP + RH / 2 - LIFT )) "out/$NAME.png"
place out/tmp_grid.png $FRONT_X $(( TOP + RH + GAP + GH / 2 )) "out/$NAME.png"
place out/tmp_logo.png $FLAP_X $BODY_Y "out/$NAME.png"   # 左の折り返し。ホックの穴の間に収める

# 右の折り返し: 文字ロゴの左に来るきらきら(case-kira。ロゴは含まない)。折って重ねたとき左の折り返しのロゴと位置が合うように、
# ロゴの外接矩形を四方に 600px 広げた枠で切ってロゴと同じ倍率で縮め、同じ向きに回して(裏返さない。折り返しは折ると
# 背面から見てそのままの向きで、左は +223、右は -2437 ずれて重なる)折り目について左のロゴと対称の位置(KIRA_X = FLAP_X + 正面の幅 x 2)に置く。
# 右の折り返しは切り線(通常 x 3414、ミニ 2596)までしか無く、折ったときロゴの右側には届かないので、きらきらはロゴの左側だけ
read -r BW BH BX BY <<<"$(magick out/tmp_flap.png -crop 2750x700+2400+3880 +repage -format '%@' info: | tr 'x+' '  ')"
KBOX="$(( BW + 1200 ))x$(( BH + 1200 ))+$(( 2400 + BX - 600 ))+$(( 3880 + BY - 600 ))"   # ロゴの外接矩形を四方に 600px 広げた枠
KSCALE="$(echo "100 * $LOGO_L / $BW" | bc -l)%"
shot out/tmp_kira.png case-kira-light
magick out/tmp_kira.png -crop "$KBOX" +repage -resize "$KSCALE" -rotate 90 out/tmp_kira.png
place out/tmp_kira.png $KIRA_X $BODY_Y "out/$NAME.png"

# 確認用: テンプレートの線(templates/ の PNG)の上に入稿データを重ねる
magick "$TPL" -resize "${CW}x${CH}!" -colorspace sRGB -type TrueColor out/tmp_tpl.png
magick out/tmp_tpl.png "out/$NAME.png" -composite -resize '1600x1600>' -dither None -colors 256 PNG8:"preview/$NAME-preview.png"
command rm -f out/tmp_*.png
magick identify -format "%f %wx%h\n" "out/$NAME.png"
