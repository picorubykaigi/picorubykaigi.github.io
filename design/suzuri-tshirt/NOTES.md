# SUZURI フルグラフィックTシャツ (PicoRubyKaigi 2026 Assemble)

Mサイズ 7535x5882px。CSS 1507x1177px をデバイススケール5でキャプチャして作る。
パターンは a（main-visual）・b（prarail）・c（parts）の 3 つ、各ライト・ダーク × 表裏。

## ファイル

| ファイル | 役割 |
| --- | --- |
| `plain.html` | デザイン本体（テンプレート・CSS）。`?capture=<面>` で1面だけ原寸表示 |
| `build.sh` | 入稿データのビルド。`./build.sh b` のようにパターン名を渡すと部分ビルド |
| `preview-sizes.sh` | M 用の入稿データを S / M / L / XL のテンプレートに当てはめたできあがりイメージ(`out/size-{light,dark}-<サイズ>.png`)。`./preview-sizes.sh b` |
| `crop-standard.sh` | 通常のTシャツ用に、入稿データの中心部(表のロゴ+パーツの周りに余白を取った範囲。a 3785×2790px、c 3480×3490px)を四角く切り出す。裏はドットの地なしの透過(`out/<パターン>-{light,dark}-{1front,2back}-standard.png`)。`./crop-standard.sh a c` |
| `can-case.sh` | フラット缶ケース用。plain.html の can(パーツと空きソケットの 4x4 格子と、その下の文字ロゴ。吹き出しも記号もなし)を地なし・透過でテンプレート(`suzuri-template-flat-can-case`)の赤線の枠に収める(`out/can-case-c.png`、確認用 `out/can-case-c-preview.png`) |
| `multi-case.sh` | クリアマルチケース用。左右を背面へ折り返してホックで留める形なので、正面に Ruby と c のパーツ 3 列 x 4 行、左の折り返し(背面)に文字ロゴ(PicoRubyKaigi / 2026 Assemble)を 90 度回して、右の折り返しには折って重ねたときロゴの左に来る位置にきらきら 5 つを置き、地なし・透過でテンプレートに置く(`out/multi-case-c.png`)。`./multi-case.sh mini` でミニ版(`out/mini-multi-case-c.png`、正面が狭いので Ruby なし)。確認用に `out/multi-case-c-preview.png`(テンプレートを重ねたもの)と `out/multi-case-c-folded-preview.png`(折って重ねた背面)も作る |
| `pdf.sh` | 印刷確認用 PDF（A4 横、1 面 1 ページ）。`out/T-shirt-1.pdf`（a・b）と `out/T-shirt-2.pdf`（c） |
| `finished.html` | できあがりイメージ（黒線で裁ち落とし・ガイド線なし） |
| `index.html` | テンプレートのガイド線つきプレビュー |
| `big.html` | できあがりイメージの拡大表示。`big.html?p=b,c&scale=.9` のようにパターンと倍率を指定 |
| `rejected.html` | 不採用案（a2 / b1 / b1s / b1d / d / e / c2 / d-emb / dnr）の保管。開くと finished 形式のできあがりイメージ。単体で完結、build.sh の対象外 |
| `gen-prarail-assets.rb` | 電車の絵(`assets/prarail.png`)からダーク用の窓の光と輪郭線(`assets/prarail-*.png`)を作る。絵を差し替えたら実行 |
| `gen-finished-assets.sh` | `assets/` の輪郭線・カバー画像を生成（テンプレート更新時のみ） |

## 決まりごと（理由つき）

- **入稿データは全面**（7535×5882px をくり抜かない）。裁ち落としは SUZURI 側。プレビューだけ黒の実線（ボディ外寸＋襟ぐり）でくり抜く。
  マスクは `assets/body_cover_*.png` から生成する。
- **表裏の柄のつながり**: 裏面は `.mirror` で左右反転。着用時に脇の縫い目・肩越しで柄が続く。
  ただし b の電車は筒に巻き付く見立てなので反転せず、表裏とも絵の同じ点（1 両目の 2 つ目の窓と 2 つ目のドアの間）が脇の縫い目に来るように置く。窓やドアを縫い目で切らない。
- **a のロゴまわりの間隔**: ロゴ→2026→Assemble のインク間隔（48px）より Assemble→パーツ列（72px）を広く（比 1.5）。
  内側の方が広いと、ロゴのかたまりとパーツが一続きに見えてバランスが悪い。
- **文字ロゴにかかる穴のドット**は JS（`knockoutDots`）が 1 個ずつ消す。消すのは、文字の字画に上下または左右を挟まれたドット（P の懐、c の口、i の点と軸の間、u・y の腕の間）と、字画に半分近く隠れるドット。縁に触れるだけのドットや角のドットは残す（部品が穴の上に載っているのと同じ見え方）。欠けたドットが一列に並ぶのと、ロゴの周りが四角く抜けるのを両方避けるため。

## ビルドの注意

各パターン × light/dark × 表裏。出力は `out/<パターン>-<mode>-{1front,2back}.png`。
全面の不透明 PNG。

- 巨大キャンバスのラスタタイル落ちで**白抜け**が出ることがある。純白が1%を超えたら
  上下2分割キャプチャ→結合に自動フォールバックする（`build.sh` 内）。GPU有効化は逆効果。
- `finished.html` はライブなので、ビルドしなくてもブラウザで最新が見られる。
- PDF はダークの発光（text-shadow）を `?print=1` で切って Chrome から直接作る。Ghostscript で圧縮・分割すると発光が矩形に潰れるか画像が消える。
