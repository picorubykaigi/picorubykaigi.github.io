#!/usr/bin/env ruby

# tour.png の文字窓。
#   使い方: ruby tools/tour_window.rb
#   出力:   tools/ogp_tour/tour-window.png (1ドット=1pxで書き出し、CSS側で4倍に拡大)

require 'zlib'

W = 270                              # ドット。1ドット=4px なので 1080x264px
H = 66
R = 5                                # 角の半径(ドット)
BLUE  = [8, 36, 168].freeze
WHITE = [255, 255, 255].freeze
CLEAR = [0, 0, 0, 0].freeze

def base
  x0 = 0
  y0 = 0
  x1 = W - 1
  y1 = H - 1
  corners = [[x0 + R, y0 + R, -1, -1], [x1 - R, y0 + R, 1, -1],
             [x0 + R, y1 - R, -1, 1],  [x1 - R, y1 - R, 1, 1]]
  Array.new(H) do |y|
    Array.new(W) do |x|
      corners.none? do |cx, cy, sx, sy|
        (x - cx) * sx > 0 && (y - cy) * sy > 0 &&
          (x - cx)**2 + (y - cy)**2 > (R + 0.5)**2
      end
    end
  end
end

# 1ドットぶん内側に削る。内側の枠は円を引き直さずこれで作るので、
# 角の階段が外側の枠と同じ形のまま、同心にずれる。
def erode(m)
  Array.new(H) do |y|
    Array.new(W) do |x|
      (-1..1).all? do |dy|
        (-1..1).all? do |dx|
          ny = y + dy
          nx = x + dx
          ny.between?(0, H - 1) && nx.between?(0, W - 1) && m[ny][nx]
        end
      end
    end
  end
end

masks = [base]
4.times { masks << erode(masks.last) }

pixels = Array.new(H) { Array.new(W) { CLEAR } }
# 外から: 白2ドット / 青1ドット / 白1ドット / 青の地
[[0, WHITE], [2, BLUE], [3, WHITE], [4, BLUE]].each do |inset, col|
  H.times do |y|
    W.times { |x| pixels[y][x] = col + [255] if masks[inset][y][x] }
  end
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

OUT = 'tools/ogp_tour/tour-window.png'
write_png(OUT, pixels, alpha: true)
puts "#{OUT} #{W}x#{H}ドット (1ドット=4pxで #{W * 4}x#{H * 4}px)"
