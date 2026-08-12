#!/bin/zsh
# tools/ogp.html (index.html のデザインを採用＋パーツ整列) を headless Chrome で
# 1200x630 にレンダリングして images/ogp.png を生成する。
# ピクセルアート(基板/Ruby/ピクセルフォント)が主役。2x→magickで縮小すると補間でにじむ。
# → device-scale-factor=2 で 2400x1260 を直接スクショし、縮小は一切しない(=リサンプリングのにじみ無し・高解像度でクリスプ)。
# OGPは大きめでも可(1.91:1のまま)。SNS側の縮小は良質フィルタなのでシャープに出る。
set -e
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=8765
SCALE=2   # 出力倍率。1=1200x630(標準) / 2=2400x1260(高精細・推奨) / 3=3600x1890
CACHE_BUST="$(date +%s)$$"   # ogp.html を直したのに前回の描画が出る(Chromeのキャッシュ)のを防ぐ

# サーバが無ければ起動
if ! curl -s -o /dev/null "http://localhost:$PORT/tools/ogp.html"; then
  (python3 -m http.server $PORT >/tmp/ogp_srv.log 2>&1 &)
  sleep 1
fi

shoot() {  # shoot <query> <out.png>
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=$SCALE --window-size=1200,630 \
    --virtual-time-budget=12000 \
    --screenshot="$2" "http://localhost:$PORT/tools/ogp.html$1${1:+&}${1:-?}cb=$CACHE_BUST" 2>/dev/null
}

shoot "" "images/ogp.png"

# Goodies で配るシンプル版(日付・会場・KEYNOTE 抜き)。会期の情報が入らないので、
# 時期を選ばず使える汎用のメインビジュアルになる。
mkdir -p images/goodies
shoot "?v=simple" "images/goodies/main-visual-simple.png"

magick identify -format "%f: %wx%h\n" images/ogp.png images/goodies/main-visual-simple.png
