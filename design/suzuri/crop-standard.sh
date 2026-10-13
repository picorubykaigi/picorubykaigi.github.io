#!/bin/bash
# 通常の(全面でない)Tシャツ用に、フルグラフィック用の入稿データから中心部を四角く切り出す。
# 範囲は表のロゴ+パーツを中心に余白を取ったもの(a: 原寸 3785x2790px、c: 3480x3490px)。通常Tシャツのプリント範囲(青枠 0.888)より横長なので、
# 載せたときは横幅いっぱいに置いて上下が生地になる。裏は全パターン共通の範囲で、ドットの地は敷かずモチーフだけ(透過)。
#   ./crop-standard.sh a c   → out/<パターン>-{light,dark}-{1front,2back}-standard.png
#                              確認用に表裏を並べた preview/<パターン>_{light,dark}-standard.png(幅 1600px)
# 要: ImageMagick(magick)。先に ./build.sh で入稿データを作っておく
set -euo pipefail
cd "$(dirname "$0")"
PATTERNS=${@:-a c}
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p preview
for p in $PATTERNS; do
  # 範囲はパターンごと: 表のロゴ+パーツ(a: x 453-1040 / y 399-757、c: x 504-1020 / y 341-849)を中心に、
  # a は左右 85px・上下 100px の余白(CSS 757x558)、c は左右 90px・上下 95px(696x698)。
  # c の左右は右にはみ出す 2026 の吹き出しを数えず、格子とロゴの幅(x 504-993)で中心を取る
  case "$p" in
    c) X=2002; Y=1230; W=3480; H=3490 ;;
    *) X=1840; Y=1495; W=3785; H=2790 ;;
  esac
  for mode in light dark; do
    # 表: 入稿データ(ドットの地つき)から切り出す
    magick "out/$p-$mode-1front-full.png" -crop "${W}x${H}+${X}+${Y}" +repage "out/$p-$mode-1front-standard.png"
    echo "out/$p-$mode-1front-standard.png"
    # 裏: ドットの地なし(モチーフだけ、背景は透過)で撮り直してから切り出す。範囲は全パターン共通
    # (CSS x 363-1130 / y 208-909 = 原寸 3835x3505px、上端は襟下 Ruby の 60px 上)で、Ruby の大きさと位置を揃える
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=5 --window-size=1507,1177 \
      --default-background-color=00000000 --virtual-time-budget=30000 --screenshot=out/tmp_back.png \
      "file://$PWD/plain.html?capture=$p-back-$mode&nodots=1" 2>/dev/null
    magick out/tmp_back.png -crop "3835x3505+1815+1040" +repage "out/$p-$mode-2back-standard.png"
    echo "out/$p-$mode-2back-standard.png"
    # 確認用: 表と裏を同じ高さにして並べ、透過は T シャツのプレビューと同じ灰色で埋める(ディザなしの 256 色で軽く)
    magick \( "out/$p-$mode-1front-standard.png" +repage -resize x2000 \) -size 80x2000 xc:'#9a9a94' \( "out/$p-$mode-2back-standard.png" +repage -resize x2000 \) \
      -background '#9a9a94' +append +repage -alpha remove -alpha off -resize 1600x -dither None -colors 256 PNG8:"preview/${p}_$mode-standard.png"
    echo "preview/${p}_$mode-standard.png"
  done
done
command rm -f out/tmp_back.png
