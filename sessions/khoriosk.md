---
title: Cortex-M7 MCUへのfemtoRubyポーティング — 限られたRAMでの構成と検証
speaker: khoriosk
kind: Talk
time: 14:55
minutes: 20
x: khoriosk
bio: 個人でPicoRuby/FemtoRubyのMCUへのポーティングに取り組んでいます。現在はCortex-M7 MCUを対象に、Ruby実行環境とhardwareの境界や、移植時に必要となる構成を確認しています。
---

本発表では、MCUの起動からFemtoRubyの実行、Rubyからの周辺機能制御まで、移植の中で取り組んだ内容を紹介する。特に限られたRAMに実行環境を収めるための構成や機能の選択について扱う。FemtoRubyとMCU依存部の境界、移植時の確認方法を整理し、今後のMCUポーティングにも利用できる形で共有する。
