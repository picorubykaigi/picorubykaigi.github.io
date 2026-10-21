# stickers.html の A(50mm) と G11(30mm) を、塗り足し 3mm 込みの印刷用 HTML にして Chrome で PDF に書き出す。
# 使い方: ruby design/sticker/print/build.rb
# 出力(design/sticker/print/):
#   a.pdf, g11.pdf            Chrome のベクター出力(RGB、文字はフォント埋め込み)
#   a_outlined.pdf, ...       文字をアウトライン化(RGB)
#   a_cmyk.pdf, g11_cmyk.pdf  さらに CMYK に変換したもの。入稿用はこれ
#   a.png, a_cmyk.png, ...    確認用プレビュー(600dpi)
#   a_cut.svg                 A のカット線 2 本(仕上げカット 50mm 角、ハーフカット 46mm 角・角丸 4mm)。テンプレートの各レイヤーに貼る
# 前提: Google Chrome, Ghostscript(gs), poppler(pdftoppm, pdftocairo), ImageMagick(magick)
# BitcountSingle-wght330-ELSH50.ttf は Google Fonts の Bitcount Single(可変、OFL)を fontTools で wght=330, ELSH=50 に固定したもの:
#   python -m fontTools.varLib.instancer BitcountSingle.woff2 wght=330 ELSH=50  (flavor を外して ttf 保存)
require "fileutils"

ROOT = File.expand_path("../../..", __dir__)
SRC = File.join(ROOT, "design/sticker/stickers.html")
OUT = __dir__
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BLEED = 3 # mm
# 画像は間引かず(ルビーのドット絵は 900ppi のまま)、JPEG 圧縮もしない
GS_IMG = %w[-dDownsampleColorImages=false -dDownsampleGrayImages=false -dDownsampleMonoImages=false -dAutoFilterColorImages=false -dColorImageFilter=/FlateEncode]
PT_PER_MM = 72 / 25.4

def chrome(*args)
  system(CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", *args, exception: true, err: File::NULL)
end

html = File.read(SRC)
style = html[/<style>\n(.*?)\n<\/style>/m, 1] or abort "style"
# 印刷用 HTML は 1 階層深い所に置くので、画像の相対パスを掛け直す
style = style.gsub("url('../../images/", "url('../../../images/").gsub("url('../shopcard/", "url('../../shopcard/")

def item(html, label)
  html.scan(/<div class="item">\n(  <div class="sticker [^"]*">.*?\n  <\/div>\n)  <div class="label">([^<]*)<\/div>/m)
      .find { |_, l| l == label }&.first or abort "item #{label}"
end

# ---- 虹色ルビー ----
# CSS の mask はヘッドレス Chrome で描けない(PDF でも落ちる)ので、グラデーションだけ Chrome で描き、
# ruby-2.png のアルファを ImageMagick で乗せて透過 PNG にする。印刷用 HTML ではこれを背景画像として置く。
# ruby-2.png は 1072×873px。13.8mm(G11 のルビー 23mm × 0.6)に置くと約 2000ppi。
ruby_mask = File.join(ROOT, "images/ruby-2.png")
ruby_png = File.join(OUT, "ruby_rainbow.png")
grad_html = File.join(OUT, "ruby_gradient.html")
grad_png = File.join(OUT, "ruby_gradient.png")
File.write(grad_html, <<~HTML)
  <!DOCTYPE html>
  <html><head><meta charset="UTF-8"><title>ruby gradient</title><style>
  html, body { margin: 0; padding: 0; }
  .g { width: 1072px; height: 873px; background: linear-gradient(118deg, #e8404b 0%, #fb5479 28%, #ffc12e 56%, #6ef0a0 76%, #55d6f2 100%); }
  </style></head><body><div class="g"></div></body></html>
HTML
chrome("--window-size=1072,873", "--screenshot=#{grad_png}", "file://#{grad_html}")
system("magick", grad_png, "(", ruby_mask, "-alpha", "extract", ")", "-compose", "CopyOpacity", "-composite", ruby_png, exception: true)
FileUtils.rm_f([grad_html, grad_png])

# ---- PARTY の文字をアウトラインに ----
# グラデーション塗りの文字(background-clip: text)は Chrome が画像にしてしまうので、
# 黒 1 色の SVG text を Chrome → Ghostscript でアウトライン化 → pdftocairo で SVG のパスにして、グラデーション塗りのパスとして置き直す。
# 字面の位置は stickers.html の実測: 文字の箱の上端 33.2mm、字面 31.44〜38.49mm、ベースライン 38.49mm。
# 字送り .14em(1.05mm)を SVG は末尾にも付けるので、中心を 0.525mm 右へずらして CSS と同じ位置にする。
party_html = File.join(OUT, "party_outline.html")
party_pdf = File.join(OUT, "party_outline.pdf")
party_svg = File.join(OUT, "party_outline.svg")
File.write(party_html, <<~HTML)
  <!DOCTYPE html>
  <html><head><meta charset="UTF-8"><title>party</title>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Jersey+10&display=swap">
  <style>@page { size: 50mm 50mm; margin: 0; } html, body { margin: 0; }</style></head><body>
  <svg viewBox="0 0 50 50" style="width: 50mm; height: 50mm; display: block"><text x="25.525" y="38.49" font-family="'Jersey 10', sans-serif" font-size="7.5" letter-spacing="1.05" text-anchor="middle" fill="#000">PARTY</text></svg>
  </body></html>
HTML
chrome("--no-pdf-header-footer", "--virtual-time-budget=15000", "--print-to-pdf=#{party_pdf}", "file://#{party_html}")
system("gs", "-q", "-o", party_pdf + ".o.pdf", "-sDEVICE=pdfwrite", "-dNoOutputFonts", party_pdf, exception: true)
system("pdftocairo", "-svg", party_pdf + ".o.pdf", party_svg, exception: true)
paths = File.read(party_svg).scan(/<path [^>]*d="([^"]+)"/).flatten
abort "party paths: #{paths.size}" unless paths.size == 5
FileUtils.rm_f([party_html, party_pdf, party_pdf + ".o.pdf", party_svg])
# パスは 50mm = 142.08pt の座標系。グラデーションは CSS の 118deg と同じ向きで、字面の外接矩形に掛ける
nums = paths.join(" ").scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
xs = nums.each_slice(2).map(&:first); ys = nums.each_slice(2).map(&:last)
bx0, bx1, by0, by1 = xs.min, xs.max, ys.min, ys.max
cx, cy, bw, bh = (bx0 + bx1) / 2, (by0 + by1) / 2, bx1 - bx0, by1 - by0
ang = 118 * Math::PI / 180
dx, dy = Math.sin(ang), -Math.cos(ang)
half = (bw * dx.abs + bh * dy.abs) / 2
grad = { x1: cx - dx * half, y1: cy - dy * half, x2: cx + dx * half, y2: cy + dy * half }.transform_values { |v| v.round(3) }
side = (50 * PT_PER_MM).round(2)
PARTY_SVG = <<~SVG.gsub(/\n\s*/, "")
  <svg class="party-svg" viewBox="0 0 #{side} #{side}" style="position:absolute;left:0;top:0;width:50mm;height:50mm">
    <defs>
      <linearGradient id="party-grad" gradientUnits="userSpaceOnUse" x1="#{grad[:x1]}" y1="#{grad[:y1]}" x2="#{grad[:x2]}" y2="#{grad[:y2]}">
        <stop offset="0" stop-color="#55d6f2"/><stop offset=".18" stop-color="#6ef0a0"/><stop offset=".36" stop-color="#6ef0a0"/>
        <stop offset=".56" stop-color="#ffc12e"/><stop offset=".8" stop-color="#fb5479"/><stop offset="1" stop-color="#e8404b"/>
      </linearGradient>
    </defs>
    <g fill="url(#party-grad)">#{paths.map { |d| %(<path d="#{d}"/>) }.join}</g>
  </svg>
SVG

# ---- 穴のドット ----
# stickers.html では 24px タイルの SVG を背景パターンにしているが、Chrome の PDF ではパターン塗り + 透明度になり、
# Illustrator に埋め込むと落ちる。印刷用では同じ見た目を、透明度なしの矩形 1 個ずつで描く(色は地色と事前に混ぜておく)。
# タイル(24 単位)内の矩形: 明るい地 = 外 (9.5,9.5)-(14.5,14.5) #39352b 11%、内 (11,11)-(16,16) #1c180e 14%
#                           暗い地 = 外 (9.5,9.5)-(14.5,14.5) #2e5247、内 (11,11)-(15,15) #16302a
def mix(base, color, alpha)
  b = base.scan(/../).map { |h| h.to_i(16) }; c = color.scan(/../).map { |h| h.to_i(16) }
  "#" + b.zip(c).map { |x, y| (x * (1 - alpha) + y * alpha).round.clamp(0, 255).to_s(16).rjust(2, "0") }.join
end

def dots_svg(w, dark:, pitch:, dot_offset:)
  p = pitch.to_f; o = dot_offset.to_f
  base = dark ? "10131c" : "eceade"
  outer = dark ? "#2e5247" : mix(base, "39352b", 0.11)
  inner = dark ? "#16302a" : mix(base, "1c180e", 0.14)
  inner_size = dark ? 4 : 5
  rects = []
  n = (w / p).ceil + 2
  (-1..n).each do |i|
    (-1..n).each do |j|
      x0 = BLEED + o + i * p; y0 = BLEED + o + j * p
      next if x0 + 16.0 / 24 * p < 0 || y0 + 16.0 / 24 * p < 0 || x0 + 9.5 / 24 * p > w || y0 + 9.5 / 24 * p > w
      f = ->(v) { v.round(3) }
      rects << %(<rect x="#{f.(x0 + 9.5 / 24 * p)}" y="#{f.(y0 + 9.5 / 24 * p)}" width="#{f.(5.0 / 24 * p)}" height="#{f.(5.0 / 24 * p)}" fill="#{outer}"/>)
      rects << %(<rect x="#{f.(x0 + 11.0 / 24 * p)}" y="#{f.(y0 + 11.0 / 24 * p)}" width="#{f.(inner_size / 24.0 * p)}" height="#{f.(inner_size / 24.0 * p)}" fill="#{inner}"/>)
    end
  end
  %(<svg class="dots" viewBox="0 0 #{w} #{w}" style="position:absolute;left:0;top:0;width:#{w}mm;height:#{w}mm" shape-rendering="crispEdges">#{rects.join}</svg>)
end

# ---- 印刷用ページ ----
# 塗り足しぶん外側まで同じ穴のドットを続ける。ドットの位相はステッカー内と同じ(左上を 3mm ずらす)
def page(style, sticker_html, size_mm, dark:, pitch:, dot_offset:)
  w = size_mm + BLEED * 2
  base = dark ? "#10131c" : "#eceade"
  dots = dots_svg(w, dark: dark, pitch: pitch, dot_offset: dot_offset)
  <<~HTML
    <!DOCTYPE html>
    <html lang="ja">
    <head>
    <meta charset="UTF-8">
    <title>sticker print</title>
    <style>
    #{style}
    @page { size: #{w}mm #{w}mm; margin: 0; }
    * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    html { background: none; }
    body { margin: 0; padding: 0; display: block; width: #{w}mm; height: #{w}mm; overflow: hidden; }
    .sheet {
      position: relative;
      width: #{w}mm;
      height: #{w}mm;
      overflow: hidden;
      background: #{base};
    }
/* ロゴの Bitcount Single は可変フォント(wght 330 / ELSH 50)だが、Chrome の PDF 出力は軸の指定を落として既定の形(丸)で埋め込む。
   fontTools の varLib.instancer で wght=330, ELSH=50 に固定した静的フォント(BitcountSingle-wght330-ELSH50.ttf、OFL)に差し替える */
@font-face {
  font-family: 'Bitcount Static';
  src: url('BitcountSingle-wght330-ELSH50.ttf') format('truetype');
}
.prk {
  font-family: 'Bitcount Static', sans-serif;
  font-variation-settings: normal;
}
    .rubyg {
      background: url('ruby_rainbow.png') center / contain no-repeat;
      -webkit-mask: none;
      mask: none;
    }
    .sheet > .sticker {
      position: absolute;
      left: #{BLEED}mm;
      top: #{BLEED}mm;
      border-radius: 0;
      background: none;
      overflow: visible;
    }
    </style>
    </head>
    <body>
    <div class="sheet">
    #{dots}
    #{sticker_html}</div>
    </body>
    </html>
  HTML
end

g11 = item(html, "G11").sub('<div class="party-text rainbow-rev-green2">PARTY</div>', PARTY_SVG)
abort "party svg" unless g11.include?("party-svg")

jobs = {
  "a"   => [item(html, "A"), 50, { dark: false, pitch: "2.556mm", dot_offset: ".642mm" }],
  "g11" => [g11,             30, { dark: true,  pitch: "2.6mm",   dot_offset: ".619mm" }],
}

jobs.each do |name, (sticker, size, opts)|
  path = File.join(OUT, "#{name}.html")
  File.write(path, page(style, sticker, size, **opts))
  pdf = File.join(OUT, "#{name}.pdf")
  chrome("--no-pdf-header-footer", "--virtual-time-budget=15000", "--print-to-pdf=#{pdf}", "file://#{path}")
  outlined = File.join(OUT, "#{name}_outlined.pdf")
  system("gs", "-q", "-o", outlined, "-sDEVICE=pdfwrite", "-dNoOutputFonts", "-dPDFSETTINGS=/prepress", *GS_IMG, pdf, exception: true)
  cmyk = File.join(OUT, "#{name}_cmyk.pdf")
  system("gs", "-q", "-o", cmyk, "-sDEVICE=pdfwrite", "-sColorConversionStrategy=CMYK", "-dProcessColorModel=/DeviceCMYK",
         "-dPDFSETTINGS=/prepress", *GS_IMG, outlined, exception: true)
  system("pdftoppm", "-r", "600", "-png", "-singlefile", outlined, File.join(OUT, name), exception: true)
  system("pdftoppm", "-r", "600", "-png", "-singlefile", cmyk, File.join(OUT, "#{name}_cmyk"), exception: true)
  puts "#{name}: pdf #{File.size(pdf)} / outlined #{File.size(outlined)} / cmyk #{File.size(cmyk)} bytes"
end

# ---- A のカット線 ----
# 塗り足し込みの 56mm 角の中に、仕上げカット(50mm 角の断裁線)と、その 2mm 内側のハーフカット(46mm 角・角丸半径 4mm)。
# プリントパックの入稿前チェック「仕上げカットパスとハーフカットパスの間は 2mm 以上」に合わせる。
# Illustrator では塗り・線なしにして、それぞれ「仕上げカット」「ハーフカット」レイヤーに置く(ここでは見えるよう色付きの線にしている)
w = 50 + BLEED * 2
File.write(File.join(OUT, "a_cut.svg"), <<~SVG)
  <svg xmlns="http://www.w3.org/2000/svg" width="#{w}mm" height="#{w}mm" viewBox="0 0 #{w} #{w}">
    <rect id="finish-cut" x="#{BLEED}" y="#{BLEED}" width="50" height="50" fill="none" stroke="#00a0e9" stroke-width=".1"/>
    <rect id="half-cut" x="#{BLEED + 2}" y="#{BLEED + 2}" width="46" height="46" rx="4" ry="4" fill="none" stroke="#e4007f" stroke-width=".1"/>
  </svg>
SVG
