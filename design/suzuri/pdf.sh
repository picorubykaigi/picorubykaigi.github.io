#!/bin/bash
# 印刷確認用 PDF(A4 横、1 面 1 ページ、ライト・ダーク × 表・裏)を作る。
# big.html を Chrome で PDF にする(文字・ドット柄はベクタのまま)。1 ファイルにすると 12MB を超えて
# プリントできないので、2 ファイルに分ける(1: a+b の 8 ページ、2: c の 4 ページ)。
# Ghostscript での圧縮・分割は、/printer でダークの発光が矩形に潰れ、それ以外の設定では Preview で画像が消えたので使わない。
# 使い方: ./pdf.sh  → out/T-shirt-1.pdf, out/T-shirt-2.pdf
# 要: Google Chrome。big.html は http 経由で開く(8798 番が空いていれば一時サーバを立てる)
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT=8798
mkdir -p out
started=""
if ! lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  (cd ../.. && python3 -m http.server $PORT >/dev/null 2>&1 &)
  started=1; sleep 1
fi
i=0
for P in "a,b" "c"; do
  i=$((i+1))
  "$CHROME" --headless=new --disable-gpu --virtual-time-budget=60000 --no-pdf-header-footer \
    --print-to-pdf="out/T-shirt-$i.pdf" "http://localhost:$PORT/design/suzuri/big.html?p=$P&scale=.9&print=1" 2>/dev/null
done
[ -n "$started" ] && pkill -f "http.server $PORT" || true
ls -la out/T-shirt-*.pdf
