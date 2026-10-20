#!/usr/bin/env ruby
# CMYK の生バイト列(magick の cmyk:-、8bit)を読み、インキ総量(C+M+Y+K)が LIMIT% を超える画素だけ K を残して CMY を同じ比率で減らす。
#   magick in.png ... -depth 8 cmyk:- | ruby ink_limit.rb 290 | magick -size WxH -depth 8 cmyk:- ... out.tif
# 入稿先の条件は合計 300% 以下(超えると不備データ)。RGB の黒を CMYK に変換すると 310% 前後になるので、その分を落とす。
# 要: なし(標準入出力だけ)

limit = (ARGV[0] || 290).to_f / 100 * 255
bytes = STDIN.binmode.read
reduced = 0
(0...bytes.bytesize).step(4) do |offset|
  cyan = bytes.getbyte(offset)
  magenta = bytes.getbyte(offset + 1)
  yellow = bytes.getbyte(offset + 2)
  black = bytes.getbyte(offset + 3)
  total = cyan + magenta + yellow + black
  next if total <= limit
  scale = (limit - black) / (cyan + magenta + yellow).to_f
  bytes.setbyte(offset, (cyan * scale).round)
  bytes.setbyte(offset + 1, (magenta * scale).round)
  bytes.setbyte(offset + 2, (yellow * scale).round)
  reduced += 1
end
STDOUT.binmode.write(bytes)
warn "ink_limit: #{reduced} 画素を #{ARGV[0] || 290}% に抑えた"
