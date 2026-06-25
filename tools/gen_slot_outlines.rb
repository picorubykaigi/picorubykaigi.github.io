#!/usr/bin/env ruby
# frozen_string_literal: true

# 各パーツPNGから「破線の輪郭」SVG(images/<part>-slot.svg)を生成する。
#
# ソケットは『破線の枠 + ドット地、形は部品のシルエット』。変更前の border:dashed と同じ
# “まっすぐ輪郭に沿った破線”にするため、シルエットを輪郭追跡してパス化し、
# SVG の stroke-dasharray で破線を描く(= dashed border と同じ原理)。
# CSS は background-image として使い、強さ(通常/誘導/ダーク)は opacity で出す。
#
# PNG のデコードは ImageMagick(magick)に委譲し、追跡/簡略化/SVG出力は純Ruby(gem不要)。
#   使い方: ruby tools/gen_slot_outlines.rb

# 元画像と、対応するソケットの表示サイズ(css px, script.js の w/h)。viewBox をこのサイズにし、
# stroke-width / dasharray を css px で直接指定できるようにする。
PARTS = {
  'chip'    => ['chip.png',    56, 56],
  'motor'   => ['motor.png',   44, 57],
  'battery' => ['battery.png', 27, 46],
}.freeze

ALPHA_TH = 40      # これ以上の不透明度をシルエット内とみなす
SS       = 4       # 追跡の精度(socketサイズの SS 倍で追跡し、座標を 1/SS に戻す)
PAD      = 3       # 周囲の余白(css px)。枠いっぱいの部品でも破線が端で切れない
RDP_EPS  = 0.5     # 輪郭の簡略化(css px)。小さいほど元の形に忠実、大きいほど滑らか
STROKE   = 2.0     # 破線の太さ(css px)。最初の border:2px dashed に合わせる
DASH     = '3 2.5' # 破線パターン(css px): 線 3 / 間 2.5(細かめ)
COLOR    = '#ffc12e'

# ImageMagick で alpha を抜き、(iw x ih) に縮小した 8bit グレースケールの生バイト列を得る
def alpha_bytes(path, iw, ih)
  raw = IO.popen(['magick', path, '-alpha', 'extract', '-filter', 'Lanczos',
                  '-resize', "#{iw}x#{ih}!", '-depth', '8', 'gray:-'], 'rb', &:read)
  raw.bytes
end

# 部品アルファを (cw*SS, ch*SS) の枠内に PAD ぶん余白を取って配置し、2値グリッドを返す
def alpha_grid(path, cw, ch)
  w = cw * SS
  h = ch * SS
  pad = PAD * SS
  iw = w - 2 * pad
  ih = h - 2 * pad
  b = alpha_bytes(path, iw, ih)
  grid = Array.new(h) { Array.new(w, 0) }
  ih.times do |y|
    iw.times do |x|
      grid[y + pad][x + pad] = 1 if b[y * iw + x].to_i > ALPHA_TH
    end
  end
  [grid, w, h]
end

# Moore 近傍による外周輪郭追跡(時計回り、Jacob の停止条件)
NEIGH = [[-1, 0], [-1, -1], [0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1]].freeze

def trace(grid, w, h)
  inside = ->(x, y) { x >= 0 && x < w && y >= 0 && y < h && grid[y][x] == 1 }
  start = nil
  (0...h).each do |y|
    (0...w).each { |x| (start = [x, y]) && break if grid[y][x] == 1 }
    break if start
  end
  return [] unless start

  idx = ->(p, c) { NEIGH.index([p[0] - c[0], p[1] - c[1]]) }
  boundary = [start]
  cur = start
  backtrack = [start[0] - 1, start[1]] # 入ってきた側(外側)
  guard = w * h * 8
  while (guard -= 1) >= 0
    s = (idx.call(backtrack, cur) + 1) % 8
    found = nil
    8.times do |k|
      i = (s + k) % 8
      nx = cur[0] + NEIGH[i][0]
      ny = cur[1] + NEIGH[i][1]
      next unless inside.call(nx, ny)

      found = [nx, ny]
      pe = (s + k - 1) % 8 # 直前に見た空セル
      backtrack = [cur[0] + NEIGH[pe][0], cur[1] + NEIGH[pe][1]]
      break
    end
    break unless found

    cur = found
    break if cur == start

    boundary << cur
  end
  boundary
end

# Ramer-Douglas-Peucker でポリラインを簡略化
def rdp(pts, eps)
  return pts.dup if pts.length < 3

  x1, y1 = pts.first
  x2, y2 = pts.last
  dx = x2 - x1
  dy = y2 - y1
  den = Math.sqrt((dx * dx) + (dy * dy))
  den = 1.0 if den.zero?
  dmax = 0.0
  at = 0
  (1...pts.length - 1).each do |i|
    px, py = pts[i]
    d = ((dy * px) - (dx * py) + (x2 * y1) - (y2 * x1)).abs / den
    (dmax = d) && (at = i) if d > dmax
  end
  if dmax > eps
    rdp(pts[0..at], eps)[0...-1] + rdp(pts[at..], eps)
  else
    [pts.first, pts.last]
  end
end

def build_svg(path, cw, ch)
  grid, w, h = alpha_grid(path, cw, ch)
  pts = trace(grid, w, h)
  return nil if pts.empty?

  pts = pts.map { |x, y| [x.to_f / SS, y.to_f / SS] }
  pts = rdp(pts, RDP_EPS)
  d = "M#{pts.map { |x, y| format('%.2f %.2f', x, y) }.join(' L')} Z"
  format(
    "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 %<cw>d %<ch>d' " \
    "width='%<cw>d' height='%<ch>d'>" \
    "<path d='%<d>s' fill='none' stroke='%<color>s' stroke-width='%<stroke>s' " \
    "stroke-dasharray='%<dash>s' stroke-linecap='butt' stroke-linejoin='round'/></svg>\n",
    cw: cw, ch: ch, d: d, color: COLOR, stroke: STROKE, dash: DASH
  )
end

Dir.chdir(File.expand_path('..', __dir__)) do # リポジトリ直下で実行
  PARTS.each do |name, (fn, cw, ch)|
    svg = build_svg("images/#{fn}", cw, ch)
    if svg.nil?
      warn "skip (empty): #{name}"
      next
    end
    File.write("images/#{name}-slot.svg", svg)
    puts "wrote images/#{name}-slot.svg"
  end
end
