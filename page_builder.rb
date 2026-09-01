# Usage: ruby page_builder.rb <out-dir>

require 'fileutils'
require_relative 'renderer'

class PageBuilder
  DESCRIPTION = 'PicoRubyKaigi 2026 Assembleは、マイコンの上で動くRuby「PicoRuby」の' \
                'カンファレンスです。2026.10.31(土)、浅草橋ヒューリックホール＆カンファレンスにて開催します。'

  # Pages that share templates/layout.html.erb, keyed by their directory: they
  # supply only their <body> content, and the layout gives them the <head> and
  # the site header. name -> <title>.
  CONTENT_PAGES = {
    'events' => 'Events',
    'sponsors' => 'Sponsors',
    'jobs' => 'Jobs',
    'team' => 'Team',
    'goodies' => 'Goodies'
  }.freeze

  # Pages that bring their own <head> (different stylesheets, fonts, OGP), so
  # they are whole documents rather than layout content. name -> output path.
  STANDALONE_PAGES = {
    'top' => 'index.html',
    'game' => 'game/index.html'
  }.freeze

  def initialize(out_dir)
    @out_dir = out_dir
  end

  def build
    CONTENT_PAGES.each do |name, title|
      write "#{name}/index.html", content_page(name, title)
    end
    STANDALONE_PAGES.each do |name, path|
      write path, Renderer.render("pages/#{name}.html.erb")
    end

    CONTENT_PAGES.length + STANDALONE_PAGES.length
  end

  private

  def content_page(name, title, description: DESCRIPTION)
    content = Renderer.render("pages/#{name}.html.erb").chomp
    Renderer.render 'layout.html.erb', title:, path: "/#{name}/", description:, content:
  end

  def write(path, html)
    dest = File.join(@out_dir, path)
    FileUtils.mkdir_p(File.dirname(dest))
    File.write(dest, html)
  end
end

if $PROGRAM_NAME == __FILE__
  out_dir = ARGV[0] || abort('usage: ruby page_builder.rb <out-dir>')
  count = PageBuilder.new(out_dir).build
  puts "Generated #{count} page(s)."
end
