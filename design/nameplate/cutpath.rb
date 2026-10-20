#!/usr/bin/env ruby
# 属性シールの絵の形にそったカットパス(切り抜き線)を作り、cutpaths.js に書き出す。
#   ruby cutpath.rb
# 手順: 絵のアルファを SCALE px/mm に縮めて、MARGIN mm ふくらませ(刃のずれ分の白フチ)、穴を埋め、
# 外周を追跡 → Douglas-Peucker で MAX_POINTS 点以下に間引き → Catmull-Rom で滑らかな閉じたパスにする。
# 絵が離れた部品に分かれていてふくらませても 1 つにならないときは、その絵だけ MARGIN を広げる。
# 入稿先の条件: アンカー 40 点以内・角 90 度以上・絵はカットパスから 2mm 内側・画像は原寸 350〜400ppi。
# サイトのドット絵(pixelated)は小さいので、最低 MIN_PPI になる整数倍に最近傍で拡大したものを images/<name>-up.png に書いて使う。
# 寸法(mm)は stickers.html と index.html に置いていた値。絵の大きさを変えるときはここを直して再実行する。
# 要: ImageMagick(magick)

SCALE = 20          # px/mm
MARGIN = 2.0        # mm。絵の端からカットパスまで
MAX_POINTS = 36     # アンカー数の上限(業者条件 40 に対し余裕)
SIZE = 1.3          # 絵の寸法にかける倍率(STICKERS の値は 20mm の丸に入れていたときのもの)
MIN_PPI = 1000      # pixelated の絵を拡大するときの下限(入稿条件 350〜400ppi に対し余裕)
STICKERS = {
  'newbie'    => { src: 'images/newbie.png', height: 8.5 },
  'led'       => { src: 'images/led.png', height: 10.6 },
  'ruby'      => { src: '../../images/ruby-mini.png', height: 8.8, pixelated: true },
  'motor'     => { src: '../../images/motor.png', height: 9.8, pixelated: true },
  'pico'      => { src: 'images/pico.png', height: 6.8 },
  'esp32'     => { src: 'images/esp32.png', height: 6.9 },
  'soldering' => { src: 'images/soldering.png', height: 10 },
  'pockecon'  => { src: 'images/pockecon.png', height: 7.5 },
  'keyboard'  => { src: 'images/keyboard.png', width: 12.7 },
  'game'      => { src: 'images/game.png', height: 6.5 },
  'sound'     => { src: 'images/sound.png', height: 7.6 },
  'sparkle'   => { src: 'images/sparkle.png', height: 7.3 },
  'wifi'      => { src: 'images/wifi.png', height: 8.8 },
}

DIRS = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]] # 東から時計回り

# 絵のアルファを 2 値化してふくらませたマスク(1 次元配列)と、その幅・高さ・パディングを返す
def dilated_mask(src, px_w, px_h, margin_mm)
  radius = (margin_mm * SCALE).round
  pad = radius + 2
  bytes = IO.popen(['magick', src, '-alpha', 'extract', '-resize', "#{px_w}x#{px_h}!", '-threshold', '25%',
                    '-bordercolor', 'black', '-border', pad.to_s,
                    '-morphology', 'Dilate', "Disk:#{radius}", '-depth', '8', 'gray:-'], 'rb', &:read)
  width = px_w + pad * 2
  height = px_h + pad * 2
  mask = Array.new(width * height) { |index| bytes.getbyte(index) > 127 }
  [mask, width, height, pad]
end

# 外側からたどれない画素をすべて前景にする(穴埋め)
def fill_holes(mask, width, height)
  outside = Array.new(mask.size, false)
  stack = [0]
  outside[0] = true
  until stack.empty?
    index = stack.pop
    x = index % width
    y = index / width
    [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].each do |nx, ny|
      next if nx < 0 || ny < 0 || nx >= width || ny >= height
      neighbour = ny * width + nx
      next if outside[neighbour] || mask[neighbour]
      outside[neighbour] = true
      stack << neighbour
    end
  end
  outside.map { |reached| !reached }
end

# 8 連結の連結成分に分け、大きい順に返す
def components(mask, width, height)
  label = Array.new(mask.size, 0)
  found = []
  mask.each_index do |start|
    next if !mask[start] || label[start] != 0
    id = found.size + 1
    pixels = []
    stack = [start]
    label[start] = id
    until stack.empty?
      index = stack.pop
      pixels << index
      x = index % width
      y = index / width
      DIRS.each do |dx, dy|
        nx = x + dx
        ny = y + dy
        next if nx < 0 || ny < 0 || nx >= width || ny >= height
        neighbour = ny * width + nx
        next if !mask[neighbour] || label[neighbour] != 0
        label[neighbour] = id
        stack << neighbour
      end
    end
    found << pixels
  end
  found.sort_by { |pixels| -pixels.size }
end

# Moore 近傍追跡で外周の画素列を返す
def trace_outline(mask, width, height)
  start = mask.index(true)
  sx = start % width
  sy = start / width
  inside = ->(x, y) { x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x] }
  outline = [[sx, sy]]
  bx, by = sx, sy
  back = 4 # 開始画素の西は背景(ラスタ順で最初の前景なので)
  first_step = nil
  loop do
    found = nil
    8.times do |turn|
      direction = (back + 1 + turn) % 8
      dx, dy = DIRS[direction]
      if inside.(bx + dx, by + dy)
        found = direction
        break
      end
    end
    break unless found
    dx, dy = DIRS[found]
    nx, ny = bx + dx, by + dy
    step = [bx, by, nx, ny]
    break if first_step && step == first_step
    first_step ||= step
    # 新しい画素から見た、直前に調べた背景画素の向き
    px, py = DIRS[(found - 1) % 8]
    back = DIRS.index([bx + px - nx, by + py - ny])
    bx, by = nx, ny
    outline << [bx, by]
  end
  outline.pop if outline.size > 1 && outline.last == outline.first
  outline
end

def point_segment_distance(point, from, to)
  px, py = point
  ax, ay = from
  bx, by = to
  dx = bx - ax
  dy = by - ay
  length2 = dx * dx + dy * dy
  t = length2.zero? ? 0 : (((px - ax) * dx + (py - ay) * dy) / length2).clamp(0, 1)
  Math.hypot(px - (ax + t * dx), py - (ay + t * dy))
end

def douglas_peucker(points, epsilon)
  return points if points.size < 3
  farthest = 0
  max_distance = 0
  (1...points.size - 1).each do |index|
    distance = point_segment_distance(points[index], points.first, points.last)
    if distance > max_distance
      max_distance = distance
      farthest = index
    end
  end
  return [points.first, points.last] if max_distance <= epsilon
  douglas_peucker(points[0..farthest], epsilon)[0...-1] + douglas_peucker(points[farthest..], epsilon)
end

# 閉じた点列を MAX_POINTS 以下に間引く
def simplify_closed(points)
  far = (1...points.size).max_by { |index| Math.hypot(points[index][0] - points[0][0], points[index][1] - points[0][1]) }
  epsilon = 0.03
  loop do
    first = douglas_peucker(points[0..far], epsilon)
    second = douglas_peucker(points[far..] + [points[0]], epsilon)
    result = first[0...-1] + second[0...-1]
    return result if result.size <= MAX_POINTS
    epsilon *= 1.25
  end
end

# Catmull-Rom で閉じた滑らかな三次ベジェにする
def smooth_path(points)
  count = points.size
  d = format('M%.2f %.2f', *points[0])
  count.times do |index|
    p0 = points[(index - 1) % count]
    p1 = points[index]
    p2 = points[(index + 1) % count]
    p3 = points[(index + 2) % count]
    c1 = [p1[0] + (p2[0] - p0[0]) / 6.0, p1[1] + (p2[1] - p0[1]) / 6.0]
    c2 = [p2[0] - (p3[0] - p1[0]) / 6.0, p2[1] - (p3[1] - p1[1]) / 6.0]
    d += format(' C%.2f %.2f %.2f %.2f %.2f %.2f', c1[0], c1[1], c2[0], c2[1], p2[0], p2[1])
  end
  d + ' Z'
end

results = {}
STICKERS.each do |name, spec|
  src = spec[:src]
  src_w, src_h = `magick identify -format "%w %h" #{src}`.split.map(&:to_i)
  if spec[:pixelated]
    factor = (MIN_PPI * ((spec[:width] || spec[:height] * src_w / src_h.to_f) * SIZE) / 25.4 / src_w).ceil
    if factor > 1
      src = "images/#{name}-up.png"
      system('magick', spec[:src], '-scale', "#{factor * 100}%", '-define', 'png:exclude-chunks=date,time', src) || abort("#{name} の拡大に失敗")
      src_w *= factor
      src_h *= factor
    end
  end
  mm_h = (spec[:height] || spec[:width] * src_h / src_w.to_f) * SIZE
  mm_w = (spec[:width] || spec[:height] * src_w / src_h.to_f) * SIZE
  px_w = (mm_w * SCALE).round
  px_h = (mm_h * SCALE).round

  margin = MARGIN
  outline = nil
  loop do
    mask, width, height, pad = dilated_mask(src, px_w, px_h, margin)
    filled = fill_holes(mask, width, height)
    parts = components(filled, width, height)
    if parts.size > 1
      margin += 0.25
      next
    end
    outline = trace_outline(filled, width, height).map { |x, y| [(x + 0.5 - pad) / SCALE, (y + 0.5 - pad) / SCALE] }
    break
  end
  warn "#{name}: MARGIN を #{margin}mm に広げてひとつにした" if margin > MARGIN

  points = simplify_closed(outline)
  xs = points.map(&:first)
  ys = points.map(&:last)
  min_x = (xs.min - 0.3).floor(1)
  min_y = (ys.min - 0.3).floor(1)
  max_x = (xs.max + 0.3).ceil(1)
  max_y = (ys.max + 0.3).ceil(1)
  shifted = points.map { |x, y| [x - min_x, y - min_y] }
  results[name] = {
    w: (max_x - min_x).round(2),
    h: (max_y - min_y).round(2),
    d: smooth_path(shifted),
    points: points.size,
    src: src,
    pixelated: spec[:pixelated] ? true : false,
    image: { x: (-min_x).round(2), y: (-min_y).round(2), w: mm_w.round(2), h: mm_h.round(2) },
  }
  puts format('%-10s %5.1f x %5.1f mm  %2d 点', name, results[name][:w], results[name][:h], points.size)
end

require 'json'
File.write('cutpaths.js', "// cutpath.rb が生成。手で編集しない\nconst CUTPATHS = #{JSON.pretty_generate(results)};\n")
