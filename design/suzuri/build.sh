#!/bin/bash
# SUZURI フルグラフィックTシャツ入稿データのビルド (Mサイズ 7535x5882px)
# plain.html の各面を CSS 1507x1177px・デバイススケール5 でキャプチャして全面のまま out/ に
# a(main-visual)/b(prarail)/c(parts: パーツの 4x3 格子+Assemble!) x ライト・ダーク x 表・裏 を作る。
# 黒の実線(ボディ外寸)の内側マスクは、確認用プレビューを T シャツ型にくり抜くときだけ使う。
# ファイル名は「パターン-モード-1front/2back-full」(色ごとに前後セットで並ぶ)。
# 要: Google Chrome, ImageMagick(magick)
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CSS_W=1507
CSS_H=1177
SCALE=5
PX_W=7535
PX_H=5882
TPL=../../suzuri-template-full-graphic-t-shirt
PATTERNS_ALL="a b c"
# 引数でパターンを指定すると、そのパターンだけリビルドする(例: ./build.sh b c)。
# 無指定なら全パターン
if [ $# -gt 0 ]; then
  PATTERNS="$@"
else
  PATTERNS=$PATTERNS_ALL
fi
echo "build: $PATTERNS"

mkdir -p out

# 黒の実線(ボディ外寸)の内側マスク(プレビューを T シャツ型にくり抜く用): finished用アセットの内側マスク(襟ぐりくり抜き済み)を
# 原寸に拡大して使う。アセットがなければ先に生成する
[ -f assets/body_cover_front.png ] || ./gen-finished-assets.sh
for side in front back; do
  mask="out/mask_$side.png"
  if [ ! -f "$mask" ]; then
    magick "assets/body_cover_$side.png" -alpha extract -negate \
      -resize "${PX_W}x${PX_H}!" -threshold 50% "$mask"
    mean=$(identify -format "%[fx:mean]" "$mask")
    echo "mask_$side mean=$mean (0.53前後が正常)"
  fi
done

num_of() {
  [ "$1" = front ] && echo 1front || echo 2back
}

shot() {  # shot <出力> <URL> <高さ> [shiftパラメータ]
  # --run-all-compositor-stages-before-draw と --disable-checker-imaging:
  # 巨大キャンバスで背景タイルが未描画のままキャプチャされる(白抜け)のを防ぐ。
  # --force-gpu-mem-available-mb: タイルメモリの上限を上げる(既定だと足りずに
  # "tile memory limits exceeded" が出て、その領域が白いまま残る)
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --run-all-compositor-stages-before-draw --disable-checker-imaging \
    --force-gpu-mem-available-mb=8192 \
    --force-device-scale-factor=$SCALE --window-size=$CSS_W,$3 \
    --virtual-time-budget=30000 --screenshot="$1" "$2${4:-}"
}

# 純白の面積比。デザインに純白はほぼ無いので、これがラスタタイル落ち(白抜け)の目印になる。
# 高さを渡すとその高さぶんだけ見る(分割キャプチャの1枚を検査するため)
white_frac() {  # white_frac <画像> [高さpx]
  magick "$1" -crop "${PX_W}x${2:-$PX_H}+0+0" +repage \
    -fuzz 2% -fill black +opaque white -fill white -opaque white \
    -format "%[fx:mean]" info:
}
bad() { [ "$(magick "$1" -crop "${PX_W}x${2:-$PX_H}+0+0" +repage \
  -fuzz 2% -fill black +opaque white -fill white -opaque white \
  -format "%[fx:mean>0.01?1:0]" info:)" = 1 ]; }

# 横帯に分割してキャプチャし、縦に結合する。1枚あたりのラスタ面積が減るので
# タイル落ちが起きにくい。落ちるかどうかは運任せなところがあるので、
# 帯ごとに検査して駄目なら撮り直す(全体を撮り直すより安い)
slice_shot() {  # slice_shot <出力> <URL> <分割数>
  local out=$1 url=$2 n=$3 base=$((CSS_H / n)) rest=$((CSS_H % n))
  local i h off=0 try parts=()
  for ((i = 0; i < n; i++)); do
    h=$base
    [ $i -lt $rest ] && h=$((base + 1))
    for try in 1 2 3; do
      shot "out/tmp_s$i.png" "$url" $h "&shift=$off"
      bad "out/tmp_s$i.png" $((h * SCALE)) || break
      echo "    帯$((i + 1))/$n を撮り直す ($try)"
    done
    parts+=("(" "out/tmp_s$i.png" -crop "${PX_W}x$((h * SCALE))+0+0" +repage ")")
    off=$((off + h))
  done
  magick "${parts[@]}" -append "$out"
  command rm -f out/tmp_s*.png
}

for p in $PATTERNS; do
  for mode in light dark; do
    for side in front back; do
      name="$p-$mode-$(num_of $side)-full"
      url="file://$PWD/plain.html?capture=$p-$side-$mode"
      shot "out/$name.png" "$url" $CSS_H
      # 白抜け検査: 純白が1%を超えたら上下2分割で撮り直す(巨大キャンバスの
      # ラスタタイル落ち対策。半分ずつなら描画が間に合う)。分割後も再検査し、
      # だめなら撮り直す。素通りさせると壊れた入稿データができてしまう
      for n in 2 4 8; do
        bad "out/$name.png" || break
        echo "  $name: 白抜け検出 (純白 $(white_frac "out/$name.png"))、${n}分割で撮り直す"
        slice_shot "out/$name.png" "$url" $n
      done
      if bad "out/$name.png"; then
        echo "  !! $name: 白抜けが直りません (純白 $(white_frac "out/$name.png"))"
      fi
      # 入稿データはくり抜かず、plain.html の全面(7535x5882)をそのまま。裁ち落としは SUZURI 側で行う
      magick "out/$name.png" -crop "${PX_W}x${PX_H}+0+0" +repage -alpha off "out/$name.png"
    done
  done
done

# 確認用プレビュー(表裏ペア)。入稿ファイルは全面なので、黒線の内側マスクで T シャツ型にくり抜く。
# プレビューは preview/ に書き、リポジトリに残す(out/ は入稿データと中間ファイルだけで、追跡しない)。
# 軽くするため、ディザなしの 256 色(PNG8)で書く
mkdir -p preview
for p in $PATTERNS; do
  for mode in light dark; do
    for side in front back; do
      magick "out/$p-$mode-$(num_of $side)-full.png" "out/mask_$side.png" \
        -alpha off -compose CopyOpacity -composite "out/cut_${mode}_$side.png"
    done
    magick \( "out/cut_${mode}_front.png" -background '#9a9a94' -alpha remove \) \
           \( "out/cut_${mode}_back.png"  -background '#9a9a94' -alpha remove \) \
           +append -resize 1600x -dither None -colors 256 PNG8:"preview/${p}_$mode-full.png"
  done
  command rm -f out/cut_*.png
done

ls -lh out/
echo "done: 入稿データ = out/<パターン>-{light,dark}-{1front,2back}-full.png (7535x5882px、全面) / プレビュー = preview/<パターン>_{light,dark}-full.png"
