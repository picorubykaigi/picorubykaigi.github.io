# images/prarail.png からダーク用の assets/prarail-glow-d.png(点灯した窓 + 段階的な光の漏れ)と
# assets/prarail-lines.png(暗い線だけ)を作る。電車の絵を差し替えたら実行する。
#   ruby gen-prarail-assets.rb [元画像] [出力先ディレクトリ]
# 画像の読み書きは ImageMagick(magick)に任せ、RGBA の生バイト列を扱う。
require 'open3'

source = ARGV[0] || '../../images/prarail.png'
out_dir = ARGV[1] || 'assets'

width, height = `magick identify -format '%w %h' #{source}`.split.map(&:to_i)
pixels, = Open3.capture2('magick', source, '-depth', '8', 'rgba:-', binmode: true)
pixels = pixels.bytes
channel = ->(x, y, c) { pixels[(y * width + x) * 4 + c] }

# 窓ガラス = 青みのある画素の塊(80 画素以上)。外接矩形で塗り直す
glass = Array.new(height) do |y|
  Array.new(width) do |x|
    r, _g, b, a = 4.times.map { |c| channel.call(x, y, c) }
    a > 0 && b - r > 18 && b < 170
  end
end
seen = Array.new(height) { Array.new(width, false) }
windows = []
height.times do |y0|
  width.times do |x0|
    next if !glass[y0][x0] || seen[y0][x0]

    seen[y0][x0] = true
    stack = [[y0, x0]]
    x_min = x_max = x0
    y_min = y_max = y0
    count = 0
    until stack.empty?
      y, x = stack.pop
      count += 1
      x_min = x if x < x_min
      x_max = x if x > x_max
      y_min = y if y < y_min
      y_max = y if y > y_max
      [[y + 1, x], [y - 1, x], [y, x + 1], [y, x - 1]].each do |ny, nx|
        next unless ny.between?(0, height - 1) && nx.between?(0, width - 1)
        next if !glass[ny][nx] || seen[ny][nx]

        seen[ny][nx] = true
        stack << [ny, nx]
      end
    end
    windows << [x_min, y_min, x_max, y_max] if count >= 80
  end
end

# 光の漏れ: 窓からの距離(チェビシェフ)を絵の 1 ドット = 5px ごとの段にして不透明度を下げる
LEVELS = [191, 140, 102, 77, 56, 38, 26, 15].freeze
glow_alpha = Array.new(width * height, 0)
windows.each do |x0, y0, x1, y1|
  reach = LEVELS.size * 5
  ([y0 - reach, 0].max..[y1 + reach, height - 1].min).each do |y|
    dy = [y0 - y, y - y1, 0].max
    ([x0 - reach, 0].max..[x1 + reach, width - 1].min).each do |x|
      distance = [[x0 - x, x - x1].max, dy].max
      value = distance <= 0 ? 255 : LEVELS[(distance - 1) / 5]
      index = y * width + x
      glow_alpha[index] = value if value > glow_alpha[index]
    end
  end
end
glow = glow_alpha.flat_map { |alpha| [255, 210, 140, alpha] }

# 暗い線: 元の絵の暗い画素だけを元の色のまま残す。窓ガラスの暗い青(映り込み)は線ではないので除く
lines = Array.new(width * height * 4, 0)
(width * height).times do |index|
  r, g, b, a = pixels[index * 4, 4]
  luminance = r * 0.299 + g * 0.587 + b * 0.114
  next unless a > 0 && luminance < 102 && b - r < 20

  lines[index * 4, 4] = [r, g, b, a]
end

[['prarail-glow-d.png', glow], ['prarail-lines.png', lines]].each do |name, data|
  Open3.capture2('magick', '-size', "#{width}x#{height}", '-depth', '8', 'rgba:-', "#{out_dir}/#{name}",
                 stdin_data: data.pack('C*'), binmode: true)
end
puts "#{windows.size} windows, #{width}x#{height}"
