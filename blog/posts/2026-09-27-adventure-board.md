---
title: オリジナル基板「Adventure Board」の試作基板とWebコンソールのご紹介
date: 2026-09-27
summary: こんにちは、PicoRubyKaigi 2026 Assembleのスタッフのkishimaです。オリジナル基板「Adventure Board」の試作と、ブラウザで動くWebコンソールについてご紹介します。
description: PicoRubyKaigi 2026 Assembleのオリジナル基板「Adventure Board」の試作と、ブラウザで動くWebコンソールについてご紹介します
---

こんにちは、PicoRubyKaigi 2026 Assembleのスタッフをしている[kishima](https://github.com/kishima)です。

[前回の記事](board.html)では、このイベントのために準備しているオリジナル基板の仕様をご紹介しました。今回は試作基板が完成したので、その基板と、ブラウザで基板のシミュレーションができる「Adventure Board Console」についてご紹介したいと思います。

---

## オリジナル基板の名前は「Adventure Board」

基板の紹介の前に、名前が決まったのでお伝えします。
前回の記事では「PicoRubyKaigi基板（仮）」と呼んでいましたが、正式な名前が **Adventure Board** に決まりました！

この基板とPicoRubyで、Lチカのその先へ冒険に出かけましょう！

---

## 試作基板が完成

最初の試作基板（R1）が手元に届き、ひととおりの機能を確かめました。

![試作基板R1を手に持ったところ。中央上に16×16のLEDマトリクスが実装されており、中央に赤いミニブレッドボードを貼りつけている](/images/blog/adventure-board-dev.jpg)

こちらが試作基板の実物です。手のひらに収まるくらいの大きさで、中央には市販のミニブレッドボードを貼りつけています。

### 基板のデバッグ

部品を実装した基板を作るのにはお金がかかりますが、量産の前に試作は欠かせません。
実際、今回も試作基板でいくつかミスを見つけて対策しました。

- USBでつないでも基板を認識しない
  - USB周りの部品の使い方の問題でした。米粒より小さな部品を剥がし、デジタル顕微鏡を使ってジャンパ線をはんだ付けして、なんとかリワークして検証しました。
- GROVEコネクタのピンの順番が逆
  - こういう初歩的な見落としがあるのが恐ろしいです。似たようなミスはやりがちなので、基板を発注する前にはよく確認したいものです。
- スピーカーからの音が汚い
  - 最初はアンプやフィルタ周りの問題かと思ってオシロスコープも使って確認していましたが、マイコン側のPWMの波形の作り方の問題でした。もう少し改善の余地はありそうです。

使ったことのないICだったので一番心配していたLEDマトリクスが、一発で動いてくれたのはありがたかったです。

音質のチェックでは、ブレッドボードも活用してRP2350のADCを音声出力の回路につなぎ、基板自身で波形を測って、その結果を使ってAIにデバッグさせたりもしました。AIから使いやすいオシロスコープがあると、デバッグもはかどりそうだなと感じました。

![音のデバッグの様子](/images/blog/adventure-board-debug.jpg)

試作で見つかった修正点は量産試作版（PV1）に反映して、今はその生産が終わるのを待っているところです。

### 動いている様子

![LEDマトリクスを点灯させた様子](/images/blog/adventure-board-led-matrix.jpg)

実際にRubyのコードでLEDマトリクスを点灯させた様子です。結構明るいです。

次のような感じで、簡単に扱えるクラスを準備しています。

```ruby
require 'adventure_board'
GC.start           # require で消費したメモリを解放
matrix = AdventureBoard.matrix

matrix.clear       # 全部消す
matrix.set(1, 1)   # x=1, y=1（左上）を点ける。xy座標の範囲は1〜16。明るさも256段階で指定できる
matrix.show        # ここでLEDが点灯する
```

---

## 「Adventure Board Console」

PicoRubyには[Webブラウザで動くターミナル](https://picoruby.org/terminal)がありますが、Adventure Boardでも簡単に使っていただけるように、シミュレータ付きのコンソールを準備しています。

Adventure Board上で動くPicoRubyを、Wasmでブラウザの中で動かせる開発環境です。基板が手元になくても、PicoRubyのコードを書いて、基板をイメージした画像の上で結果を見ることができます。

以下の動画に使ってみた様子をまとめているので、ご覧ください。

<video src="/images/blog/adventure-board-console-demo.mp4" poster="/images/blog/adventure-board-console-demo.jpg" controls muted playsinline preload="metadata" style="width:100%;height:auto"></video>

ここで書いたコードは、そのまま基板でも動くようになっています。

次のようなことができます。

### LEDマトリクス・ボタン・スピーカー

基板の絵の上のボタンをマウスでクリックして押したり、キーボードで操作したりできます。音も鳴ります。

![Webコンソールの画面](/images/blog/adventure-board-console-1.jpg)

### ブレッドボード

あらかじめ用意された部品（ジャンパ線・抵抗・LED・タクトスイッチ）をブレッドボードの穴に挿して、簡単な回路を組めます。実際に電流を計算していて、抵抗の数でLEDの明るさが変わります。抵抗を入れ忘れたり、GNDとショートしたりしていると注意が出ます。

![ブレッドボードを拡大した画面](/images/blog/adventure-board-console-2.jpg)

### 実機に転送して実行

基板をUSBでつなぎ、Web Serialで接続すると、書いたコードをワンタッチで基板に送ってすぐに実行できます（ChromeとEdgeで使えます）。

ターミナルとしてもつながっているので、R2P2のWebコンソールとしても使えます。

![実機に接続した画面](/images/blog/adventure-board-console-connected.jpg)

ちなみに、このWebコンソールの画面も、PicoRuby.wasmとFunicular（PicoRuby.wasmのUIフレームワーク）を使って、Rubyで書いています。

Adventure Board Consoleは、イベントまでに公開する予定です。

---

## おわりに

Adventure Boardは、ご希望の方に有償で予約販売する予定です。
準備が進みましたら、またSNS等でお知らせしますので、お楽しみに。

2026年10月31日(土)、浅草橋ヒューリックホール＆カンファレンスでお会いしましょう。
