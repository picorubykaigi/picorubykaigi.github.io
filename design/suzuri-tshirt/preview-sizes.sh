#!/bin/bash
# M サイズ用の入稿データ(out/<パターン>-{light,dark}-{1front,2back}.png)を S / M / L / XL のテンプレートに
# 当てはめたできあがりイメージを作る(SUZURI はサイズごとの画像を受け付けず、1 枚の画像を各サイズの推奨サイズに
# 引き伸ばすものとして、推奨サイズへ非等倍に拡大縮小してからそのサイズの黒線でくり抜く)。
#   ./preview-sizes.sh b   → out/size-{light,dark}-{S,M,L,XL}.png(表裏ペア、幅 1600px)
# 要: ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"
P=${1:-b}
TPL=../../suzuri-template-full-graphic-t-shirt
SCALE=0.2  # テンプレート原寸に対する作業倍率

num_of() { [ "$1" = front ] && echo 1front || echo 2back; }

for size in S M L XL; do
  for mode in light dark; do
    parts=()
    for side in front back; do
      tpl="$TPL/$side/$size/$(echo $size | tr 'A-Z' 'a-z')_$side.png"
      w=$(magick identify -format '%w' "$tpl"); h=$(magick identify -format '%h' "$tpl")
      sw=$(printf '%.0f' "$(echo "$w*$SCALE" | bc -l)"); sh=$(printf '%.0f' "$(echo "$h*$SCALE" | bc -l)")
      # 黒線(暗く低彩度)だけ → 説明文の矩形を消す → 外側と襟ぐりを塗りつぶしてボディの内側マスクに
      magick "$tpl" -background white -alpha remove -alpha off -resize "${sw}x${sh}!" out/tmp_flat.png
      magick out/tmp_flat.png -colorspace Gray -threshold 45% -negate out/tmp_dark.png
      magick out/tmp_flat.png -channel RGB -separate +channel -evaluate-sequence Max out/tmp_max.png
      magick out/tmp_flat.png -channel RGB -separate +channel -evaluate-sequence Min out/tmp_min.png
      magick out/tmp_min.png out/tmp_max.png -compose minus -composite -threshold 15% -negate out/tmp_lowc.png
      rx0=$(printf '%.0f' "$(echo "$sw*0.279" | bc -l)"); ry0=$(printf '%.0f' "$(echo "$sh*0.417" | bc -l)")
      rx1=$(printf '%.0f' "$(echo "$sw*0.723" | bc -l)"); ry1=$(printf '%.0f' "$(echo "$sh*0.561" | bc -l)")
      magick out/tmp_dark.png out/tmp_lowc.png -compose multiply -composite \
        -fill black -draw "rectangle $rx0,$ry0 $rx1,$ry1" -threshold 20% out/tmp_line.png
      magick out/tmp_line.png -bordercolor black -border 2 -fill white -floodfill +0+0 black -shave 2x2 out/tmp_f.png
      nx=$(printf '%.0f' "$(echo "$sw*0.501" | bc -l)")
      ny=$(printf '%.0f' "$(echo "$sh*$([ $side = front ] && echo 0.068 || echo 0.038)" | bc -l)")
      magick out/tmp_f.png -fill white -draw "color $nx,$ny floodfill" -negate out/tmp_mask.png
      # 入稿データをそのサイズに引き伸ばし、マスクでくり抜いて灰色の地に置き、黒線を重ねる
      magick "out/$P-$mode-$(num_of $side).png" -resize "${sw}x${sh}!" out/tmp_mask.png \
        -alpha off -compose CopyOpacity -composite -background '#9a9a94' -alpha remove out/tmp_cut.png
      magick out/tmp_cut.png \( out/tmp_line.png -negate -alpha off -fill '#333' -opaque black -transparent white \) \
        -compose over -composite "out/tmp_$side.png"
      parts+=("out/tmp_$side.png")
    done
    magick "${parts[@]}" +append -resize 1600x "out/size-$mode-$size.png"
    echo "out/size-$mode-$size.png"
  done
done
command rm -f out/tmp_*.png
