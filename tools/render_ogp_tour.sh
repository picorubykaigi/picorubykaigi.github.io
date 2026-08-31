#!/bin/zsh
# tools/ogp_tour.html を headless Chrome で 1200x630 にレンダリングして
# images/events/tour.png (Day 2 電子部品お買い物ツアー のイベント画像) を生成する。
# 隣に並ぶ images/events/followup.png / party.png と同じ 1200x630・等倍。
set -e
cd "$(dirname "$0")/.."
# サーバは要らない(file:// で読む)。ブラウザで見たいときは npm run dev の
# http://localhost:8916/tools/ogp_tour.html へ。
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 背景と窓のドット絵を先に書き出す
ruby tools/tour_map.rb
ruby tools/tour_window.rb

mkdir -p images/events
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --window-size=1200,630 --virtual-time-budget=12000 \
  --screenshot="images/events/tour.png" \
  "file://$PWD/tools/ogp_tour.html" 2>/dev/null

magick identify -format "tour: %wx%h\n" images/events/tour.png
