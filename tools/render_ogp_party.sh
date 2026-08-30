#!/bin/zsh
# tools/ogp_party.html を headless Chrome で 1200x630 にレンダリングして
# images/events/party.png (Day 1 Official Party のイベント画像) を生成する。
# 隣に並ぶ images/events/followup.png と同じ 1200x630・等倍。
set -e
cd "$(dirname "$0")/.."
# サーバは要らない(file:// で読む)。ブラウザで見たいときは npm run dev の
# http://localhost:8916/tools/ogp_party.html へ。
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 引数に数字を渡すと、紙吹雪ときらめきの散らし方を振り直せる。
# 第1引数=画面上半分の種 / 第2引数=下半分の種(例: ./tools/render_ogp_party.sh 4242 777)。
QUERY=""
[ -n "${1:-}" ] && QUERY="?seed=$1"
[ -n "${2:-}" ] && QUERY="${QUERY:-?}${QUERY:+&}seedb=$2"

mkdir -p images/events
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --window-size=1200,630 --virtual-time-budget=12000 \
  --screenshot="images/events/party.png" \
  "file://$PWD/tools/ogp_party.html$QUERY" 2>/dev/null

magick identify -format "party: %wx%h\n" images/events/party.png
