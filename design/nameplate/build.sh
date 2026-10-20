#!/bin/bash
# 名札の入稿用画像のビルド(design/shopcard/build.sh と同じ流儀)
# index.html を 600dpi 相当でキャプチャし、ロールごとの TIFF を作る。
#   ./build.sh   → out/{attendee,speaker,staff}.tif(CMYK) out/{attendee,speaker,staff}.png(RGB、確認用) preview/nameplate-{attendee,speaker,staff}.png
# どれも仕上がり 100x148mm + 塗り足し 3mm の 106x154mm で、トンボなし。TIFF は Japan Color 2001 Coated に変換して埋め込み、
# インキ総量を ink_limit.rb で 290% 以下にしたもの(入稿先の条件 300% 以下)。Affinity に貼るのは TIFF。preview/ は塗り足しを落とした仕上がり 100x148mm を 1/4 に縮めたプレビュー(out/ は重いので追跡せず、preview/ だけ追跡する)。
# 入稿先は Affinity から PDF/X-4 で書き出す運用なので、Affinity のドキュメント(100x148mm、裁ち落とし 3mm、400dpi、CMYK Japan Color 2001 Coated)に
# この TIFF を裁ち落とし枠いっぱい(左上 -3,-3mm)に貼り、コーナートンボ付きで書き出す。同じプロファイルなので再変換されない。
# 要: Google Chrome, ImageMagick(magick), Affinity(同梱の JapanColor2001Coated.icc を使う)
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# はがき 100x148mm + 塗り足し3mm = 106x154mm = CSS 400.6x582px。600dpiで2504x3638px
CSS_W=401
CSS_H=582
SCALE=6.25
PX_W=2504
PX_H=3638
BLEED=71     # 塗り足し 3mm
TRIM_W=2362  # 仕上がり 100mm
TRIM_H=3496  # 仕上がり 148mm
ICC="/Applications/Affinity.app/Contents/Resources/JapanColor2001Coated.icc"
SRGB="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
mkdir -p out preview

for role in attendee speaker staff; do
  png="out/$role.png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=$SCALE --window-size=$CSS_W,$CSS_H \
    --virtual-time-budget=20000 \
    --screenshot="$png" "file://$PWD/index.html?capture=$role&marks=0" 2>/dev/null
  magick "$png" -crop "${PX_W}x${PX_H}+0+0" +repage \
    -density 600 -units PixelsPerInch "$png"
  magick "$png" -profile "$SRGB" -intent relative -black-point-compensation -profile "$ICC" -depth 8 cmyk:- \
    | ruby ink_limit.rb 290 \
    | magick -size ${PX_W}x${PX_H} -depth 8 cmyk:- -profile "$ICC" -density 600 -units PixelsPerInch -compress lzw "out/$role.tif"
  magick "$png" -crop "${TRIM_W}x${TRIM_H}+${BLEED}+${BLEED}" +repage -resize 25% -strip "preview/nameplate-$role.png"
done

echo "done: out/{attendee,speaker,staff}.tif preview/nameplate-{attendee,speaker,staff}.png (106x154mm, 塗り足し3mm込み, トンボなし)"
