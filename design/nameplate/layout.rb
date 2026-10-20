#!/usr/bin/env ruby
# 属性シールの A5 面付け(シート納品のマルチタイプ A5・1 シート 40 個配置)。
#   ruby cutpath.rb && ruby layout.rb
# 同じ絵柄を 1 本の横帯にする。帯は横に並べると幅が足りないので、1 行に 1〜2 本置く(ROWS)。行の間は全幅の仕切り線、同じ行の帯の間は短い縦の仕切り線。
# 似た絵柄をまとめて 1 本の帯にする(間に仕切り線を入れない)ときは、ROWS の中で配列にする。
# 2 本の行は、仕切り線の左右それぞれの中央に帯が来る位置に仕切る(端の余白が足りない行だけ左右に寄せる)。
# 枠数は「同じシートを SHEETS 枚刷る」前提で、絵柄ごとの必要枚数 ÷ SHEETS の切り上げ(余った 2 枠は Ruby と LED)。
# シート端から MARGIN、仕切り線から CUT_MARGIN、シール同士は GAP 以上あけ、余った分は仕切り線のまわりに均等に足す。

require 'json'

SHEET_W = 148.0
SHEET_H = 210.0
MARGIN = 6.0      # mm。シート端からカットパスまで
CUT_MARGIN = 4.0  # mm。仕切り線からカットパスまで
GAP = 4.0         # mm。同じ帯の中のカットパス同士の間
SHEETS = 20
SLOTS = {
  'newbie' => 2, 'led' => 5, 'ruby' => 6, 'motor' => 2, 'pico' => 4, 'esp32' => 4, 'soldering' => 3,
  'pockecon' => 2, 'keyboard' => 2, 'game' => 2, 'sound' => 3, 'sparkle' => 3, 'wifi' => 2,
}
ROWS = [%w[ruby], %w[pico newbie], %w[esp32 motor], %w[led sound], %w[pockecon keyboard], %w[soldering sparkle], %w[game wifi]]

cutpaths = JSON.parse(File.read('cutpaths.js').sub(/\A.*?const CUTPATHS = /m, '').sub(/;\s*\z/, ''))
abort "枠数 #{SLOTS.values.sum} が 40 ではない" unless SLOTS.values.sum == 40
abort 'ROWS と SLOTS の絵柄が合わない' unless ROWS.flatten.sort == SLOTS.keys.sort

# 帯 = 絵柄の配列(1 つか、仕切り線なしでつなげる複数)
strip_width = ->(strip) { Array(strip).sum { |name| cutpaths[name]['w'] * SLOTS[name] } + GAP * (Array(strip).sum { |name| SLOTS[name] } - 1) }
row_height = ->(strips) { strips.flatten.map { |name| cutpaths[name]['h'] }.max }

usable_w = SHEET_W - MARGIN * 2
rows_height = ROWS.sum { |strips| row_height.(strips) }
spacing_y = CUT_MARGIN * 2 + (SHEET_H - MARGIN * 2 - rows_height - CUT_MARGIN * 2 * (ROWS.size - 1)) / (ROWS.size - 1)
abort "行が縦に収まらない(間隔 #{spacing_y.round(1)}mm)" if spacing_y < CUT_MARGIN * 2

placed = []
cuts = []
y = MARGIN
ROWS.each_with_index do |strips, row_index|
  abort '1 行に置ける帯は 2 本まで' if strips.size > 2
  height = row_height.(strips)
  widths = strips.map(&strip_width)
  # 帯の左端の x と、帯の間の仕切り線の x
  if strips.size == 1
    starts = [(SHEET_W - widths[0]) / 2]
    cut_x = nil
  elsif SHEET_W - widths.sum >= [MARGIN, CUT_MARGIN].max * 4
    # 仕切り線の左右それぞれの中央に帯が来る位置に仕切る(余白は両側に均等)
    cut_x = (SHEET_W + widths[0] - widths[1]) / 2
    starts = [(cut_x - widths[0]) / 2, cut_x + (SHEET_W - cut_x - widths[1]) / 2]
  else
    # 中央に寄せると端の余白が足りない行は、帯を左右に寄せて間に仕切り線を置く
    spacing_x = usable_w - widths.sum
    abort "#{strips.flatten.join('+')} が横に収まらない(間隔 #{spacing_x.round(1)}mm)" if spacing_x < CUT_MARGIN * 2
    starts = [MARGIN, MARGIN + widths[0] + spacing_x]
    cut_x = MARGIN + widths[0] + spacing_x / 2
  end
  top = row_index.zero? ? 0 : y - spacing_y / 2
  bottom = row_index == ROWS.size - 1 ? SHEET_H : y + height + spacing_y / 2
  strips.each_with_index do |strip, strip_index|
    x = starts[strip_index]
    Array(strip).each do |name|
      SLOTS[name].times do
        placed << { name: name, x: x.round(2), y: (y + (height - cutpaths[name]['h']) / 2).round(2) }
        x += cutpaths[name]['w'] + GAP
      end
    end
  end
  cuts << { x: cut_x.round(2), y1: top.round(2), y2: bottom.round(2) } if cut_x
  cuts << { y: bottom.round(2) } if row_index < ROWS.size - 1
  y += height + spacing_y
end

layout = { sheet: { w: SHEET_W, h: SHEET_H }, cuts: cuts, items: placed }
File.write('layout.js', "// layout.rb が生成。手で編集しない\nconst LAYOUT = #{JSON.pretty_generate(layout)};\n")
puts "#{placed.size} 個 / #{ROWS.size} 行(行間 #{spacing_y.round(1)}mm) / #{SHEETS} シートで #{SLOTS.map { |name, count| "#{name} #{count * SHEETS}" }.join(', ')}"
