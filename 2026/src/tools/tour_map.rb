#!/usr/bin/env ruby

# tour.png の背景。16x16ドットのタイルを敷き詰める。
# 断面は上から 車道 / 縁石 / 歩道 / 点字ブロック。
# 1ドット=4px で表示する前提なので、ここでは1ドット=1pxで書き出す。
#   使い方: ruby tools/tour_map.rb
#   出力:   tools/ogp_tour/tour-map.png

require 'zlib'

T  = 16                 # タイルの一辺(ドット)
GW = 300                # 画面ぜんぶ(1200x632px を 4px/ドットで割った大きさ)
GH = 158

AS  = [70, 74, 92].freeze;    ASD = [56, 60, 78].freeze;    ASL = [88, 92, 112].freeze
SW  = [200, 188, 164].freeze; SWJ = [164, 150, 124].freeze; SWL = [224, 214, 194].freeze
CBL = [224, 214, 196].freeze; CBD = [96, 98, 114].freeze
MHD = [50, 52, 64].freeze;    MHL = [102, 106, 120].freeze
TB  = [204, 176, 104].freeze; TBL = [228, 204, 144].freeze
TBD = [164, 136, 68].freeze;  TBJ = [184, 156, 88].freeze

def tile(base, h = T, w = T)
  Array.new(h) { Array.new(w) { base } }
end

def asphalt
  t = tile(AS)
  [[2, 3], [9, 1], [13, 6], [5, 9], [11, 12], [1, 14], [7, 7]].each do |x, y|
    t[y][x] = ASD
    t[y][x + 1] = ASD
  end
  [[6, 2], [12, 9], [3, 12]].each { |x, y| t[y][x] = ASL }
  t
end

def sidewalk
  t = tile(SW)
  T.times do |i|
    t[0][i] = SWJ
    t[8][i] = SWJ
    t[i][0] = SWJ
    t[i][8] = SWJ
  end
  (1..7).each { |i| t[1][i] = SWL; t[9][i] = SWL }   # 敷石の上端に光
  [[4, 5], [12, 13]].each { |x, y| t[y][x] = SWJ }
  t
end

def manhole
  t = asphalt
  T.times do |y|
    T.times do |x|
      r = (x - 7.5)**2 + (y - 7.5)**2
      next if r > 36

      t[y][x] = r >= 20 || r <= 13 ? MHL : MHD
    end
  end
  t
end

# 点字ブロック1枚。size=1辺のドット数。バーは常に4本。
# dashed=true で、バーをブロックの内側で止めて継ぎ目を作る(=横に破線)。
def guide(size, dashed: true)
  bar = size / 4
  t = tile(TBJ, size, size)
  inner = dashed ? (1..size - 2) : (0..size - 1)
  4.times do |i|
    r = i * bar
    inner.each do |x|
      t[r][x] = TBL
      (r + 1...r + bar - 1).each { |y| t[y][x] = TB } if bar >= 3
      t[r + bar - 1][x] = TBD
    end
  end
  t
end

AS_T = asphalt
SW_T = sidewalk
MH_T = manhole

FAR_SW  = [0, 16].freeze
FAR_CB  = [16, 18].freeze
ROAD    = [18, 118].freeze
NEAR_CB = [118, 120].freeze
NEAR_SW = [120, GH].freeze

# dx, dy はタイルの敷き始めの位相。継ぎ目や濃い段が画像の端に重ならないようにずらす。
def lay(m, y0, y1, tl, dx: 0, dy: 0)
  h = tl.size
  w = tl[0].size
  (y0...y1).each do |y|
    row = tl[(y - y0 + dy) % h]
    GW.times { |x| m[y][x] = row[(x + dx) % w] }
  end
end

def build(size, dashed)
  m = Array.new(GH) { Array.new(GW) { [0, 0, 0] } }
  lay(m, *ROAD, AS_T)
  lay(m, *FAR_SW, SW_T, dx: 2, dy: 4)
  lay(m, *NEAR_SW, SW_T, dx: 2)
  [FAR_CB, NEAR_CB].each do |a, b|
    GW.times { |x| m[a][x] = CBL; m[b - 1][x] = CBD }
  end
  T.times { |y| T.times { |x| m[6 * T + y][13 * T + x] = MH_T[y][x] } }   # マンホール
  # 上端は明るい段から始め、下端はバーの途中で切れるよう 1 ドット短く敷く
  lay(m, GH - size + 1, GH, guide(size, dashed: dashed), dx: 2)
  m
end

# 各行の先頭にフィルタ種別0を置いた生バイト列を deflate して PNG にする。
def write_png(path, rows, alpha: false)
  h = rows.size
  w = rows[0].size
  raw = rows.map { |row| ([0] + row.flatten).pack('C*') }.join
  chunks = [
    ['IHDR', [w, h, 8, alpha ? 6 : 2, 0, 0, 0].pack('NNC5')],
    ['IDAT', Zlib::Deflate.deflate(raw, 9)],
    ['IEND', ''],
  ]
  out = +"\x89PNG\r\n\x1a\n".b
  chunks.each do |type, data|
    out << [data.bytesize].pack('N') << type << data.b
    out << [Zlib.crc32(type + data)].pack('N')
  end
  File.binwrite(path, out)
end

OUT = 'tools/ogp_tour/tour-map.png'
write_png(OUT, build(16, true))
puts "#{OUT} #{GW}x#{GH}ドット (1ドット=4pxで #{GW * 4}x#{GH * 4}px)"
