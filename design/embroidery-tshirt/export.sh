#!/bin/bash
# 刺繍の入稿データを out/ に書き出す。
#   out/back-logo.png   背中ロゴ(透過 PNG、1cm = 157px)
#   out/chest-ruby.png  左胸 Ruby(透過 PNG、1cm = 157px)
#   out/color-guide.png 色指示(糸番号つき)
#   out/embroidery.zip  上の 3 つ
# index.html?capture=<面>&transparent=1 をヘッドレス Chrome で地を透過にして撮り(デバイススケール 10 =
# 1507px → 15070px)、magick -trim でインクの外接矩形に切り出す。寸法は px / 157 = cm。
# 要: Google Chrome、ImageMagick(magick)、zip
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p out

shot() {  # shot <出力> <URL> <デバイススケール> <横> <縦>
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor="$3" --window-size="$4,$5" \
    --default-background-color=00000000 --virtual-time-budget=5000 \
    --screenshot="$1" "$2" 2>/dev/null
}

shot out/tmp.png "file://$PWD/index.html?capture=oatmeal-back&transparent=1" 10 1507 1177
magick out/tmp.png -trim +repage out/back-logo.png
shot out/tmp.png "file://$PWD/index.html?capture=oatmeal-front&transparent=1" 10 1507 1177
magick out/tmp.png -trim +repage out/chest-ruby.png
command rm -f out/tmp.png

for f in back-logo chest-ruby; do
  magick identify -format "$f.png: %w x %h px = %[fx:w/157] x %[fx:h/157] cm = %[fx:w*h/157/157] cm2\n" "out/$f.png"
done

# 色指示は書き出した PNG を貼って作るので、上の 2 つのあとで撮る
shot out/color-guide.png "file://$PWD/color-guide.html" 2 1700 1060

(cd out && command rm -f embroidery.zip && zip -q embroidery.zip back-logo.png chest-ruby.png color-guide.png)
ls -la out/
