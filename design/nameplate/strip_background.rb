#!/usr/bin/env ruby
# 画像生成で作ったシール用の絵(リポジトリ直下に置いたもの)から、まわりの地(生成りのベージュ・穴のドット・透過済みなら薄いゴミ)を抜いて透過 PNG にする。
#   ruby strip_background.rb ../../keyboard.png images/keyboard.png
# 抜くのは画像の外周から地の色をたどって届く範囲だけ。輪郭線で囲まれた内側は、地と同じ色でも触らない。
# 地の判定は彩度の低いベージュ(#eae7da 前後の地と #d8d2be 前後の穴)と、不透明度 10% 未満の画素。
# images/newbie.png と images/led.png は手で切り抜いたものが正なので、このスクリプトで上書きしない。
# 要: ImageMagick(magick)

src, dst = ARGV
abort "usage: ruby strip_background.rb SRC.png DST.png" unless src && dst

width, height = `magick identify -format "%w %h" #{src}`.split.map(&:to_i)
pixels = IO.popen(['magick', src, '-depth', '8', 'rgba:-'], 'rb', &:read)

def beige?(red, green, blue)
  max = [red, green, blue].max / 255.0
  min = [red, green, blue].min / 255.0
  lightness = (max + min) / 2
  return false if lightness < 0.6 || max == min
  saturation = (max - min) / (1 - (2 * lightness - 1).abs)
  return false unless saturation.between?(0.1, 0.5)
  hue = if max == red / 255.0
          60 * ((green - blue) / 255.0 / (max - min)) % 360
        elsif max == green / 255.0
          60 * ((blue - red) / 255.0 / (max - min)) + 120
        else
          60 * ((red - green) / 255.0 / (max - min)) + 240
        end
  hue.between?(30, 65)
end

background = ->(index) do
  offset = index * 4
  alpha = pixels.getbyte(offset + 3)
  alpha < 26 || beige?(pixels.getbyte(offset), pixels.getbyte(offset + 1), pixels.getbyte(offset + 2))
end

# 外周の地から 4 近傍で広げる
visited = Array.new(width * height, false)
queue = []
width.times { |x| queue << x << (height - 1) * width + x }
height.times { |y| queue << y * width << y * width + width - 1 }
queue.each { |index| visited[index] = true if background.(index) }
queue.select! { |index| visited[index] }
until queue.empty?
  index = queue.shift
  x = index % width
  y = index / width
  [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].each do |nx, ny|
    next if nx < 0 || ny < 0 || nx >= width || ny >= height
    neighbour = ny * width + nx
    next if visited[neighbour] || !background.(neighbour)
    visited[neighbour] = true
    queue << neighbour
  end
end
visited.each_with_index { |reached, index| pixels.setbyte(index * 4 + 3, 0) if reached }

# 余白は不透明な範囲で詰める
IO.popen(['magick', '-size', "#{width}x#{height}", '-depth', '8', 'rgba:-', '-strip', dst], 'wb') do |io|
  io.write(pixels)
end
box = `magick #{dst} -alpha extract -threshold 10% -format "%@" info:`.strip
system('magick', dst, '-crop', box, '+repage', dst)
puts `magick identify -format "%f %wx%h\n" #{dst}`
