# 刺繍Tシャツ (PicoRubyKaigi 2026 Assemble)

左胸(着用者の左)に Ruby マーク、背中の肩甲骨の間に文字ロゴを刺繍する T シャツ。
このフォルダだけで完結する。

## ファイル

| ファイル | 役割 |
| --- | --- |
| `index.html` | デザイン本体。開くと T シャツ形のできあがりイメージ(`?scale=` で倍率)。`?capture=oatmeal-back` で 1 面の原寸、`&transparent=1` で地を塗らない |
| `export.sh` | 入稿データの書き出し(`out/back-logo.png`, `out/chest-ruby.png`, `out/color-guide.png`, `out/embroidery.zip`) |
| `color-guide.html` | 色指示(糸番号と使用箇所を書き込んだ図)。`out/` の PNG を貼るので `export.sh` が先 |
| `assets/ruby-1-thread.png` | Ruby マークを糸 2 色に塗り分けた絵(`images/ruby-1.png` の 57 個のドットを、320 を地に G≥93 の明るいドット 21 個だけ 14 に) |
| `assets/body_cover_*.png`, `assets/blackline_*.png` | できあがりイメージ用の T シャツの形(suzuri-tshirt からコピー) |

## 面

| 名前 | 内容 |
| --- | --- |
| oatmeal | オートミール生地(#d9d3c5) |
| black | 黒生地(#111111)。糸色は oatmeal と共通 |

## 寸法と色

座標系は SUZURI M テンプレートと同じ 1507x1177px(1px ≈ 0.637mm)。書き出しはデバイススケール 10 で 1cm = 157px。

- 背中ロゴ: 約 25.4 x 4.3cm(109cm²。刺繍の上限 110cm² ぎりぎりまで大きくした)。PicoRubyKaigi 43.5px・字間 .15em、2026 35px、Assemble 29px(1 文字の幅 7mm 前後)。縁取りはすべて 1mm。
- 左胸 Ruby: 高さ 70px = 約 5.4 x 4.4cm(24cm²。上限 25cm² 内)。縁取りなし。
- 糸は 5 色(色見本 color.png の番号): 320 ローズ(Ruby の暗いドット・PicoRuby の縁)、14 ピンク(Ruby の明るいドット・PicoRuby の塗り)、8653 白(Kaigi・2026 Assemble の塗り)、1738 濃紺(Kaigi の縁)、22678 シルバーグレー(2026 Assemble の縁)。
- 画面の色は色見本の写真から取った近似。写真は全体に暗いので、黒糸 23100 → #1a1a1a、白糸 8653 → #eeeeee を基準にした直線補正をかけた値(320 と 14 は補正前の値のまま)。

## 決まりごと

- 文字ロゴの縁取りは 2 層: 下に同じ文字を縁の色で 32 方向にずらして重ね(text-shadow、丸い結合になるので棘が出ない)、上に塗りと同色の細い縁取りで Bitcount の要素の隙間を埋める。これで外側だけに縁が付き、要素どうしの間に線が出ない。
- 2026 Assemble は text-stroke(半分が外に出るので 1mm の縁に 3.2px)。
- 2026 Assemble の塗りは白(8653)、縁は 22678。
