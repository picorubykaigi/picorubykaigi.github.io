#!/bin/bash
# finished.html(できあがりイメージ表示)用アセットの生成
# テンプレートから以下を作る:
#   assets/blackline_{front,back}.png — 黒い線(ボディ外寸・襟など)だけの透過PNG
#   assets/body_cover_{front,back}.png — 黒ボディ線の外側(+襟ぐり)をページ地色で覆う透過PNG
# 黒線の抽出 = 暗い かつ 彩度が低い画素(赤線・青線は彩度が高いので除外)。
# 中央の説明文は矩形で消す。
# 要: ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"

TPL=templates/suzuri-template-full-graphic-t-shirt
mkdir -p assets

# 襟ぐり(ボディ線に囲まれた首の穴)を塗りつぶすための内点
NECK_X=755

for side in front back; do
  case $side in
    front) NECK_Y=80 ;;
    back)  NECK_Y=45 ;;
  esac
  flat=assets/tmp_flat.png
  magick "$TPL/$side/M/m_${side}.png" -background white -alpha remove -alpha off "$flat"

  # 暗い画素(白=暗い)
  magick "$flat" -colorspace Gray -threshold 45% -negate assets/tmp_dark.png
  # 彩度が低い画素(白=低彩度)。max(RGB)-min(RGB)が小さいもの
  magick "$flat" -channel RGB -separate +channel -evaluate-sequence Max assets/tmp_max.png
  magick "$flat" -channel RGB -separate +channel -evaluate-sequence Min assets/tmp_min.png
  magick assets/tmp_min.png assets/tmp_max.png -compose minus -composite \
    -threshold 15% -negate assets/tmp_lowc.png
  # 黒線 = 暗い x 低彩度。説明文は矩形で消す
  magick assets/tmp_dark.png assets/tmp_lowc.png -compose multiply -composite \
    -fill black -draw "rectangle 2100,2450 5450,3300" assets/tmp_line.png

  # 黒線オーバーレイ: RGB=黒 / アルファ=線。表示サイズ用に1/5へ縮小
  magick assets/tmp_line.png -resize "1507x1177!" \
    \( -clone 0 -negate \) +swap -alpha off -compose CopyOpacity -composite \
    "assets/blackline_$side.png"

  # ボディ内側マスク: 1/5スケールで外側→襟ぐりの順に塗りつぶし→反転。
  # フラッドフィルは他処理と混ぜると暴発するのでコマンドを分ける
  magick assets/tmp_line.png -resize "1507x1177!" -threshold 20% assets/tmp_s.png
  magick assets/tmp_s.png -bordercolor black -border 2 \
    -fill white -floodfill +0+0 black -shave 2x2 assets/tmp_f.png
  magick assets/tmp_f.png -fill white -draw "color $NECK_X,$NECK_Y floodfill" assets/tmp_f2.png
  # ボディの外側(+襟ぐり)をページ地色で覆うオーバーレイ。
  # CSSマスクは file:// の画像を受け付けない(CORS)ので <img> 重ねで抜く
  magick -size 1507x1177 xc:'#b9b9b3' assets/tmp_f2.png \
    -alpha off -compose CopyOpacity -composite "assets/body_cover_$side.png"
  mean=$(identify -format "%[fx:mean]" assets/tmp_f2.png)
  echo "body_cover_$side coverage mean=$mean (0.45前後が正常)"

  command rm -f assets/tmp_*.png
done

echo "done: assets/blackline_{front,back}.png assets/body_mask_{front,back}.png"
