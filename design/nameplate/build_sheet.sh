#!/bin/bash
# 属性シールの入稿データ(A5 面付け)のビルド。
#   ./build_sheet.sh → out/stickers-a5-print.pdf(印刷用。カットパスの線なし) out/stickers-a5-cutpath.pdf(カットパス入りの見本) out/stickers-a5.zip(両方) out/stickers-a5-{print,cutpath}.png(低解像度のプレビュー。PDF と zip は重いので追跡せず、これだけ追跡する)
# 入稿先は Illustrator 以外で作るとき「カットパス入りの見本」と「カットパスを消した印刷用データ」の 2 点入稿。
# Chrome の PDF は RGB なので、Ghostscript で CMYK に変換する(画像は間引かない。透過はそのまま残る)。ファイル名は半角英数字。
# 要: Google Chrome, Ghostscript(gs), zip
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p out
tmp=$(mktemp -d)
trap 'command rm -rf "$tmp"' EXIT

ruby cutpath.rb
ruby layout.rb
for mode in print cutpath; do
  query=""
  [ "$mode" = cutpath ] && query="?cut"
  "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --virtual-time-budget=20000 \
    --print-to-pdf="$tmp/$mode.pdf" "file://$PWD/sheet.html$query" 2>/dev/null
  gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 \
    -sColorConversionStrategy=CMYK -dProcessColorModel=/DeviceCMYK -dOverrideICC \
    -dDownsampleColorImages=false -dDownsampleGrayImages=false \
    -dAutoFilterColorImages=false -dColorImageFilter=/FlateEncode \
    -dAutoFilterGrayImages=false -dGrayImageFilter=/FlateEncode \
    -sOutputFile="out/stickers-a5-$mode.pdf" "$tmp/$mode.pdf"
done
for mode in print cutpath; do
  gs -q -dNOPAUSE -dBATCH -sDEVICE=png16m -r120 -sOutputFile="out/stickers-a5-$mode.png" "out/stickers-a5-$mode.pdf"
done
command rm -f out/stickers-a5.zip
(cd out && zip -q stickers-a5.zip stickers-a5-print.pdf stickers-a5-cutpath.pdf)
echo "done: out/stickers-a5-print.pdf out/stickers-a5-cutpath.pdf out/stickers-a5.zip out/stickers-a5-{print,cutpath}.png (A5 148x210mm, CMYK)"
