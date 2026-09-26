---
title: PicoRubyで作る|PicoRuby開発環境
speaker: youchan
kind: Talk
time: 15:20
minutes: 20
github: youchan
x: youchan
bio: PicoPicoRuby(共同)主催者
---

PicoRuby(.wasm)で作られたPicoRubyの開発ツールとしては、R2P2 Web Terminalがあります。
R2P2 Web TerminalはPicoRuby上で動くRubyのコードを書くことができます。
しかし、実際のPicoRubyによるマイコンボードの開発においてはC言語の実装が必要になるケースが多くあります。
mrbgemを開発する場合、C言語のライブラリを呼びだす必要がある場合、パフォーマンス要件や低レイヤを直接制御する場合などC言語で実装する必要があるケースがあります。
しかし、C言語で開発した機能をPicoRubyに組み込むにはPicoRubyのイメージのビルドが必要になります。ビルド環境を構築するのはPicoRubyの開発におけるひとつの大きなハードルです。

ここで言うPicoRubyの開発環境とは、R2P2 Web TerminalのようなWebブラウザ上で動く
- C言語のファイルの編集ができて
- ビルドが可能な
- ビルドしたイメージをマイコンにインストールできる

ような開発環境を目指しています。

本トークでは、PicoRubyの開発環境の開発の進捗と技術的な解説を行ないます。
