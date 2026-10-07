# Assemble the Keynote template as a .pptx with real slide layouts.
#
# Keynote turns the layouts of an imported .pptx into master slides, so this is
# how the template gets masters without hand work. Run export_assets.sh first;
# it renders the backgrounds, logos and layout-*.json files this script reads.
#
#   ruby build_pptx.rb out/keynote out/picorubykaigi2026.pptx

require 'cgi'
require 'fileutils'
require 'json'
require 'tmpdir'

EMU_PER_PX = 12700
NAMESPACES = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ' \
             'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' \
             'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
XML_HEADER = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n)
REL_BASE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

INK = '26242F'
RED = 'E8404B'
LIT = 'FF9E73'
MUTED = '6C675A'
CODE = 'ECE9DF'
CODE_COLORS = { keyword: 'FF6B78', string: 'FFC12E', constant: '8FB0EE', number: '6EF0A0' }

def px(value) = (value * EMU_PER_PX).round
def hundredths_pt(px_size) = (px_size * 100).round
def escape(text) = CGI.escapeHTML(text)

def xfrm((left, top, width, height))
  %(<a:xfrm><a:off x="#{px(left)}" y="#{px(top)}"/><a:ext cx="#{px(width)}" cy="#{px(height)}"/></a:xfrm>)
end

def run_props(size, color, font, tracking, bold)
  %(<a:defRPr sz="#{hundredths_pt(size)}"#{bold ? ' b="1"' : ''} spc="#{hundredths_pt(size * tracking)}"><a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>) +
    %(<a:latin typeface="#{font}"/><a:ea typeface="#{font}"/><a:cs typeface="#{font}"/></a:defRPr>)
end

# tracking is the CSS letter-spacing in em, line the CSS line-height in percent.
# Line spacing is given in points: Keynote applies a percentage to the font's own
# line height, which for the Japanese body font is far taller than the CSS line box.
def level(number, size:, color: INK, font:, align: 'l', bullet: nil, indent: 0, margin: 0, before: 0, line: 100, tracking: 0, bold: false)
  %(<a:lvl#{number}pPr marL="#{px(margin)}" indent="#{px(-indent)}" algn="#{align}">) +
    %(<a:lnSpc><a:spcPts val="#{hundredths_pt(size * line / 100.0)}"/></a:lnSpc><a:spcBef><a:spcPts val="#{hundredths_pt(before)}"/></a:spcBef>) +
    (bullet || '<a:buNone/>') + run_props(size, color, font, tracking, bold) + %(</a:lvl#{number}pPr>)
end

def image_bullet(rel_id, size_percent)
  %(<a:buSzPct val="#{size_percent * 1000}"/><a:buBlip><a:blip r:embed="#{rel_id}"/></a:buBlip>)
end

# tile is the rel id of an image repeated over the box, tile_scale its size in percent
def placeholder(id, name, ph, rect, levels, text, anchor: 't', tile: nil, tile_scale: 100, padding: [0, 0])
  scale = (tile_scale * 1000).round
  fill_xml = tile ? %(<a:blipFill dpi="0" rotWithShape="1"><a:blip r:embed="#{tile}"/><a:srcRect/>) +
                    %(<a:tile tx="0" ty="0" sx="#{scale}" sy="#{scale}" flip="none" algn="tl"/></a:blipFill>) : ''
  horizontal, vertical = padding.map { |value| px(value) }
  %(<p:sp><p:nvSpPr><p:cNvPr id="#{id}" name="#{name}"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr>#{ph}</p:nvPr></p:nvSpPr>) +
    %(<p:spPr>#{xfrm(rect)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>#{fill_xml}</p:spPr>) +
    %(<p:txBody><a:bodyPr wrap="square" lIns="#{horizontal}" tIns="#{vertical}" rIns="#{horizontal}" bIns="#{vertical}" anchor="#{anchor}"><a:noAutofit/></a:bodyPr>) +
    %(<a:lstStyle>#{levels.join}</a:lstStyle><a:p><a:r><a:rPr lang="en-US"/><a:t>#{escape(text)}</a:t></a:r></a:p></p:txBody></p:sp>)
end

SLIDE_NUMBER_PH = '<p:ph type="sldNum" sz="quarter" idx="12"/>'

# On the layout it carries the position and style; on a slide it only points at the layout.
def slide_number(id, rect = nil)
  shape_props = rect ? %(<p:spPr>#{xfrm(rect)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>) : '<p:spPr/>'
  body_props = rect ? %(<a:bodyPr wrap="none" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr"/>) : '<a:bodyPr/>'
  styles = rect ? level(1, size: 32, font: 'Zen Kaku Gothic New', align: 'r', tracking: 0.1) : ''
  %(<p:sp><p:nvSpPr><p:cNvPr id="#{id}" name="Slide Number"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>) +
    %(<p:nvPr>#{SLIDE_NUMBER_PH}</p:nvPr></p:nvSpPr>#{shape_props}<p:txBody>#{body_props}<a:lstStyle>#{styles}</a:lstStyle>) +
    %(<a:p><a:fld id="{B6F15528-21DE-4FAA-801E-634DDDAF4B2B}" type="slidenum"><a:rPr lang="en-US"/><a:t>‹#›</a:t></a:fld></a:p></p:txBody></p:sp>)
end

def static_text(id, name, rect, text, size:, font:, spacing: 0)
  %(<p:sp><p:nvSpPr><p:cNvPr id="#{id}" name="#{name}"/><p:cNvSpPr txBox="1"/><p:nvPr userDrawn="1"/></p:nvSpPr>) +
    %(<p:spPr>#{xfrm(rect)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>) +
    %(<p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr"/><a:lstStyle/>) +
    %(<a:p><a:pPr algn="ctr"/><a:r><a:rPr lang="en-US" sz="#{hundredths_pt(size)}" spc="#{hundredths_pt(spacing)}">) +
    %(<a:solidFill><a:srgbClr val="#{INK}"/></a:solidFill><a:latin typeface="#{font}"/></a:rPr>) +
    %(<a:t>#{escape(text)}</a:t></a:r></a:p></p:txBody></p:sp>)
end

def picture(id, name, rel_id, rect)
  %(<p:pic><p:nvPicPr><p:cNvPr id="#{id}" name="#{name}"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr userDrawn="1"/></p:nvPicPr>) +
    %(<p:blipFill><a:blip r:embed="#{rel_id}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>) +
    %(<p:spPr>#{xfrm(rect)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>)
end

def background(rel_id)
  %(<p:bg><p:bgPr><a:blipFill dpi="0" rotWithShape="1"><a:blip r:embed="#{rel_id}"/>) +
    %(<a:stretch><a:fillRect/></a:stretch></a:blipFill><a:effectLst/></p:bgPr></p:bg>)
end

def shape_tree(shapes)
  %(<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>) +
    %(<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>) +
    shapes.join + %(</p:spTree>)
end

def relationships(entries)
  XML_HEADER + %(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">) +
    entries.map.with_index(1) { |(type, target), index| %(<Relationship Id="rId#{index}" Type="#{type}" Target="#{target}"/>) }.join +
    %(</Relationships>)
end

# bullet: false spells out "no bullet"; Keynote otherwise draws a stray dot on body text
def paragraph(depth, runs, bullet: true)
  runs = [[' ', nil, false]] if runs.empty?
  properties = bullet ? %(<a:pPr lvl="#{depth}"/>) : %(<a:pPr lvl="#{depth}"><a:buNone/></a:pPr>)
  %(<a:p>#{properties}) + runs.map do |text, color, bold|
    fill = color ? %(<a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>) : ''
    %(<a:r><a:rPr lang="en-US"#{bold ? ' b="1"' : ''}>#{fill}</a:rPr><a:t>#{escape(text)}</a:t></a:r>)
  end.join + %(</a:p>)
end

def filled(ph, name, id, paragraphs)
  %(<p:sp><p:nvSpPr><p:cNvPr id="#{id}" name="#{name}"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr>#{ph}</p:nvPr></p:nvSpPr>) +
    %(<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>#{paragraphs.join}</p:txBody></p:sp>)
end

THEME = XML_HEADER + <<~XML.delete("\n")
  <a:theme #{NAMESPACES} name="PicoRubyKaigi 2026"><a:themeElements>
  <a:clrScheme name="PicoRubyKaigi"><a:dk1><a:srgbClr val="#{INK}"/></a:dk1><a:lt1><a:srgbClr val="ECEADE"/></a:lt1>
  <a:dk2><a:srgbClr val="16141C"/></a:dk2><a:lt2><a:srgbClr val="F6F4EA"/></a:lt2>
  <a:accent1><a:srgbClr val="#{RED}"/></a:accent1><a:accent2><a:srgbClr val="5F7CB8"/></a:accent2>
  <a:accent3><a:srgbClr val="#{LIT}"/></a:accent3><a:accent4><a:srgbClr val="FFC12E"/></a:accent4>
  <a:accent5><a:srgbClr val="6EF0A0"/></a:accent5><a:accent6><a:srgbClr val="#{MUTED}"/></a:accent6>
  <a:hlink><a:srgbClr val="5F7CB8"/></a:hlink><a:folHlink><a:srgbClr val="5F7CB8"/></a:folHlink></a:clrScheme>
  <a:fontScheme name="PicoRubyKaigi"><a:majorFont><a:latin typeface="DotGothic16"/><a:ea typeface="DotGothic16"/><a:cs typeface=""/></a:majorFont>
  <a:minorFont><a:latin typeface="Zen Kaku Gothic New"/><a:ea typeface="Zen Kaku Gothic New"/><a:cs typeface=""/></a:minorFont></a:fontScheme>
  <a:fmtScheme name="PicoRubyKaigi"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>
  <a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="25400"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="38100"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>
  <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>
  <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>
  </a:themeElements></a:theme>
XML

class Package
  def initialize(assets)
    @assets = assets
    @files = {}
    @media = {}
  end

  attr_reader :files

  # Returns the package path of the image, copying it into ppt/media once.
  def media(name)
    @media[name] ||= begin
      path = "ppt/media/image#{@media.size + 1}.png"
      @files[path] = File.binread(File.join(@assets, name))
      path
    end
  end

  def write(output)
    Dir.mktmpdir do |dir|
      @files.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
        File.binwrite(File.join(dir, path), content)
      end
      FileUtils.rm_f(output)
      system('zip', '-q', '-X', '-r', File.expand_path(output), '[Content_Types].xml', '_rels', 'ppt', chdir: dir, exception: true)
    end
  end
end

assets_dir, output = ARGV
layout = Dir[File.join(assets_dir, 'layout-*.json')].map { |path| JSON.parse(File.read(path)) }.reduce(:merge)
logo_rect = ->(name) do
  size, left, top = File.read(File.join(assets_dir, "logo-#{name}.geometry")).strip.split('+')
  width, height = size.split('x')
  [left.to_f / 2, top.to_f / 2, width.to_f / 2, height.to_f / 2]
end

package = Package.new(assets_dir)
title_style = [level(1, size: 64, font: 'DotGothic16', tracking: 0.1)]
slide_title_rect = [100, 25, 1720, 120]
number_rect = [1640, 1006, 180, 56]
# Body layouts relate rId3 = footer logo, rId4 / rId5 = bullet images (see body_layout).
# The first bullet image carries its glow as padding, so the text box starts
# BULLET_OVERHANG px left of the HTML content box to put the square where the HTML has it.
BULLET_OVERHANG = 14
bullet_levels = [
  level(1, size: 52, font: 'Zen Kaku Gothic New', bullet: image_bullet('rId4', 88),
           indent: 64 + BULLET_OVERHANG, margin: 64 + BULLET_OVERHANG, before: 34, line: 135),
  level(2, size: 42, font: 'Zen Kaku Gothic New', bullet: image_bullet('rId5', 32),
           indent: 47, margin: 116 + BULLET_OVERHANG, before: 14, line: 135),
]
overhang = ->((left, top, width, height)) { [left - BULLET_OVERHANG, top, width + BULLET_OVERHANG, height] }
code_levels = (1..5).map { |number| level(number, size: 40, color: CODE, font: 'Menlo', line: 138, margin: 16) }
code_rect = layout['03-code']['.code']

# Each layout: [name, background image, images on the layout, shapes built from the image rel ids]
# Body layouts relate extra_images from rId6 on.
body_layout = ->(name, background_image, shapes, extra_images = []) do
  [name, background_image, ['logo-footer.png', 'bullet-1.png', 'bullet-2.png', *extra_images], ->(logo_id, *) do
    [placeholder(2, 'Title', '<p:ph type="title"/>', slide_title_rect, title_style, 'Title', anchor: 'ctr'),
     *shapes,
     picture(20, 'Logo', logo_id, logo_rect.('footer')),
     slide_number(21, number_rect)]
  end]
end
title = layout['01-title']
layouts = [
  ['Title', '01-title-background.png', ['logo-lockup.png'], ->(logo_id) do
    [picture(2, 'Logo', logo_id, logo_rect.('lockup')),
     placeholder(3, 'Title', '<p:ph type="ctrTitle"/>', [200, 380, 1520, 287],
                 [level(1, size: 112, font: 'DotGothic16', align: 'ctr', line: 128, tracking: 0.04)], 'Your slide title', anchor: 'ctr'),
     placeholder(4, 'Name', '<p:ph type="subTitle" idx="1"/>', [200, title['.speaker-name'][1], 1520, title['.speaker-name'][3]],
                 [level(1, size: 56, font: 'DotGothic16', align: 'ctr', line: 120, tracking: 0.04)], 'Your name here', anchor: 'ctr'),
     static_text(5, 'Date', title['.talk-date'], '2026.10.31.', size: 34, font: 'DotGothic16', spacing: 3.4)]
  end],
  body_layout.('Title & Bullets', '02-about-me-background.png', [
    placeholder(3, 'Body', '<p:ph type="body" idx="1"/>', overhang.([100, 230, 1720, 750]), bullet_levels, 'Text'),
  ]),
  body_layout.('Title & Code', '02-about-me-background.png', [
    placeholder(3, 'Code', '<p:ph type="body" idx="1"/>', code_rect, code_levels, 'Code', tile: 'rId6', tile_scale: 37.5, padding: [64, 48]),
  ], ['code-tile.png']),
  body_layout.('Title Only', '02-about-me-background.png', []),
]

code = [
  [['require', :keyword], [' ', nil], ["'gpio'", :string]],
  [],
  [['led = ', nil], ['GPIO', :constant], ['.new(', nil], ['25', :number], [', ', nil], ['GPIO', :constant], ['::', nil], ['OUT', :constant], [')', nil]],
  [],
  [['loop do', :keyword]],
  [['  led.write ', nil], ['1', :number]],
  [['  sleep ', nil], ['0.5', :number]],
  [['  led.write ', nil], ['0', :number]],
  [['  sleep ', nil], ['0.5', :number]],
  [['end', :keyword]],
]
# Each slide: [layout index, shapes, images placed on the slide (related from rId2 on)]
slides = [
  [0, [filled('<p:ph type="ctrTitle"/>', 'Title', 2, [paragraph(0, [['Your slide title', nil, false]])]),
       filled('<p:ph type="subTitle" idx="1"/>', 'Name', 3, [paragraph(0, [['Your name here', nil, false]])])]],
  [1, [filled('<p:ph type="title"/>', 'Title', 2, [paragraph(0, [['About me', nil, false]])]),
       filled('<p:ph type="body" idx="1"/>', 'Body', 3, [
         paragraph(0, [['Your ', nil, false], ['name', RED, true]]),
         paragraph(1, [['More profile', nil, false]]),
       ]),
       picture(4, 'Photo Frame', 'rId2', layout['02-about-me']['.photo'])], ['photo-frame.png']],
  [2, [filled('<p:ph type="title"/>', 'Title', 2, [paragraph(0, [['L-chika', nil, false]])]),
       filled('<p:ph type="body" idx="1"/>', 'Code', 3,
              code.map { |line| paragraph(0, line.map { |text, kind| [text, CODE_COLORS[kind], false] }, bullet: false) })]],
]

types = {
  layout: "#{REL_BASE}/slideLayout", master: "#{REL_BASE}/slideMaster", slide: "#{REL_BASE}/slide",
  theme: "#{REL_BASE}/theme", image: "#{REL_BASE}/image", document: "#{REL_BASE}/officeDocument",
}

layouts.each.with_index(1) do |(name, background_image, images, build), number|
  rels = [[types[:master], '../slideMasters/slideMaster1.xml']]
  rels << [types[:image], "../media/#{File.basename(package.media(background_image))}"]
  images.each { |image| rels << [types[:image], "../media/#{File.basename(package.media(image))}"] }
  shapes = build.(*images.each_index.map { |index| "rId#{index + 3}" })
  package.files["ppt/slideLayouts/slideLayout#{number}.xml"] = XML_HEADER +
    %(<p:sldLayout #{NAMESPACES} preserve="1"><p:cSld name="#{escape(name)}">#{background('rId2')}#{shape_tree(shapes)}</p:cSld>) +
    %(<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>)
  package.files["ppt/slideLayouts/_rels/slideLayout#{number}.xml.rels"] = relationships(rels)
end

package.files['ppt/slideMasters/slideMaster1.xml'] = XML_HEADER +
  %(<p:sldMaster #{NAMESPACES}><p:cSld>#{background('rId1')}#{shape_tree([])}</p:cSld>) +
  %(<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>) +
  %(<p:sldLayoutIdLst>#{layouts.each_index.map { |index| %(<p:sldLayoutId id="#{2147483649 + index}" r:id="rId#{index + 2}"/>) }.join}</p:sldLayoutIdLst></p:sldMaster>)
package.files['ppt/slideMasters/_rels/slideMaster1.xml.rels'] = relationships(
  [[types[:image], "../media/#{File.basename(package.media('02-about-me-background.png'))}"]] +
  layouts.each_index.map { |index| [types[:layout], "../slideLayouts/slideLayout#{index + 1}.xml"] } +
  [[types[:theme], '../theme/theme1.xml']]
)
package.files['ppt/theme/theme1.xml'] = THEME

slides.each.with_index(1) do |(layout_index, shapes, images), number|
  layout_number = layout_index + 1
  shapes += [slide_number(21)] unless layout_index.zero?
  package.files["ppt/slides/slide#{number}.xml"] = XML_HEADER +
    %(<p:sld #{NAMESPACES}><p:cSld>#{shape_tree(shapes)}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>)
  package.files["ppt/slides/_rels/slide#{number}.xml.rels"] = relationships(
    [[types[:layout], "../slideLayouts/slideLayout#{layout_number}.xml"]] +
    Array(images).map { |image| [types[:image], "../media/#{File.basename(package.media(image))}"] }
  )
end

package.files['ppt/presentation.xml'] = XML_HEADER +
  %(<p:presentation #{NAMESPACES}><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>) +
  %(<p:sldIdLst>#{slides.each_index.map { |index| %(<p:sldId id="#{256 + index}" r:id="rId#{index + 2}"/>) }.join}</p:sldIdLst>) +
  %(<p:sldSz cx="#{px(1920)}" cy="#{px(1080)}"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>)
package.files['ppt/_rels/presentation.xml.rels'] = relationships(
  [[types[:master], 'slideMasters/slideMaster1.xml']] +
  slides.each_index.map { |index| [types[:slide], "slides/slide#{index + 1}.xml"] } +
  [[types[:theme], 'theme/theme1.xml']]
)
package.files['_rels/.rels'] = relationships([[types[:document], 'ppt/presentation.xml']])

content_type = 'application/vnd.openxmlformats-officedocument.presentationml'
overrides = { 'ppt/presentation.xml' => "#{content_type}.presentation.main+xml",
              'ppt/slideMasters/slideMaster1.xml' => "#{content_type}.slideMaster+xml",
              'ppt/theme/theme1.xml' => 'application/vnd.openxmlformats-officedocument.theme+xml' }
layouts.each_index { |index| overrides["ppt/slideLayouts/slideLayout#{index + 1}.xml"] = "#{content_type}.slideLayout+xml" }
slides.each_index { |index| overrides["ppt/slides/slide#{index + 1}.xml"] = "#{content_type}.slide+xml" }
package.files['[Content_Types].xml'] = XML_HEADER +
  %(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) +
  %(<Default Extension="png" ContentType="image/png"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) +
  %(<Default Extension="xml" ContentType="application/xml"/>) +
  overrides.map { |path, type| %(<Override PartName="/#{path}" ContentType="#{type}"/>) }.join + %(</Types>)

package.write(output)
