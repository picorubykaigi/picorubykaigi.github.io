#!/bin/zsh
# tools/logo.html (index.html と同じ styles.css を読む) を headless Chrome でレンダリングし、
# Goodies ページで配布するロゴ画像を images/goodies/ に書き出す。
#
#   logo-horizontal.png  横組み(PicoRubyKaigi を1行で)
#   logo-vertical.png    縦組み(PicoRuby / Kaigi を2行で)
#
# ロゴマーク(logomark.png)は手で切り抜いたものをそのまま置いている。
# このスクリプトでは生成しない(実行しても上書きされない)。
#
# 文字サイズは logo.html 側で固定しているのでウィンドウの大きさに左右されない。
# ここでの --window-size は、ロゴが折り返さず収まる大きさであればよい。
# ピクセルフォント+6pxの枠なので、縮小せず device-scale-factor で直接高精細に撮る。
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=8765
SCALE=4        # 出力倍率(112px のロゴ→448px相当でスクショ)
PAD_RATIO=0.08 # trim 後に付け直す余白(高さに対する比率)

OUT=images/goodies
CACHE_BUST="$(date +%s)$$"   # logo.html を直したのに前回の描画が出る(Chromeのキャッシュ)のを防ぐ
mkdir -p "$OUT"

if ! curl -s -o /dev/null "http://localhost:$PORT/tools/logo.html"; then
  (python3 -m http.server $PORT >/tmp/logo_srv.log 2>&1 &)
  sleep 1
fi

# 透過のまま撮って余白を切り、比率で余白を付け直す(素材ごとに余白量が揃う)。
shoot() {  # shoot <query> <out.png>
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --default-background-color=00000000 \
    --force-device-scale-factor=$SCALE --window-size=1440,1000 \
    --virtual-time-budget=12000 \
    --screenshot="$2" "http://localhost:$PORT/tools/logo.html$1${1:+&}${1:-?}cb=$CACHE_BUST" 2>/dev/null
  magick "$2" -trim +repage \
    -bordercolor none -border "$(magick "$2" -trim +repage -format "%[fx:round(h*$PAD_RATIO)]" info:)" \
    "$2"
}

shoot "" "$OUT/logo-horizontal.png"
shoot "?shape=vertical" "$OUT/logo-vertical.png"

magick identify -format "%f: %wx%h\n" "$OUT/logo-horizontal.png" "$OUT/logo-vertical.png"
