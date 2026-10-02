# Usage: ruby page_builder.rb <out-dir>

require 'fileutils'
require 'kramdown'
require 'kramdown-parser-gfm'
require_relative 'renderer'

class PageBuilder
  DESCRIPTION = 'PicoRubyKaigi 2026 Assembleは、マイコンの上で動くRuby「PicoRuby」の' \
                'カンファレンスです。2026.10.31(土)、浅草橋ヒューリックホール＆カンファレンスにて開催します。'

  # Pages that share templates/layout.html.erb, keyed by their directory: they
  # supply only their <body> content, and the layout gives them the <head> and
  # the site header. name -> <title>.
  CONTENT_PAGES = {
    'schedule' => 'Schedule',
    'events' => 'Events',
    'speakers' => 'Speakers',
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

  # One Markdown file per session in sessions/<handle>.md: the front matter has
  # the title, speaker, kind, time and accounts, and the body is the abstract.
  # A `|` in the title or the speaker's name marks where it may break: `title` and `speaker` are
  # the HTML with those breaks, `title_label` and `speaker_label` the plain text. `\n` in the bio is a line break.
  SESSIONS_DIR = File.join(__dir__, 'sessions')

  def initialize(out_dir)
    @out_dir = out_dir
  end

  def build
    CONTENT_PAGES.each do |name, title|
      write "#{name}/index.html", content_page(name, title, sessions:)
    end
    STANDALONE_PAGES.each do |name, path|
      write path, Renderer.render("pages/#{name}.html.erb")
    end
    sessions.each_value do |session|
      write "schedule/#{session[:handle]}/index.html", session_page(session)
    end

    CONTENT_PAGES.length + STANDALONE_PAGES.length + sessions.length
  end

  private

  def content_page(name, title, description: DESCRIPTION, **locals)
    content = Renderer.render("pages/#{name}.html.erb", **locals).chomp
    Renderer.render 'layout.html.erb', title:, path: "/#{name}/", description:, content:
  end

  def session_page(session)
    content = Renderer.render('pages/session.html.erb', session:).chomp
    description = session[:abstract_html] ? excerpt(session[:abstract_html], 120) : DESCRIPTION
    Renderer.render 'layout.html.erb',
      title: "#{session[:title_label]} - #{session[:speaker_label]}",
      path: "/schedule/#{session[:handle]}/",
      description:,
      content:
  end

  def sessions
    @sessions ||= Dir.glob(File.join(SESSIONS_DIR, '*.md')).sort.to_h do |file|
      meta, body = parse_frontmatter(File.read(file))
      handle = File.basename(file, '.md')
      title = meta['title'].to_s
      speaker = meta['speaker'].to_s
      [handle, {
        handle:,
        title: breakable(title, '') { |part| %(<span class="title-part">#{part}</span>) },
        title_label: title.delete('|'),
        speaker: breakable(speaker, '<wbr>') { |part| part },
        speaker_label: speaker.delete('|'),
        bio: meta['bio']&.gsub('\\n', "\n"),
        kind: meta['kind'].downcase.to_sym,
        kind_label: meta['kind'],
        time: meta['time'],
        minutes: meta['minutes'].to_i,
        github: meta['github'],
        x: meta['x'],
        abstract_html: body.strip.empty? ? nil : markdown_to_html(body)
      }]
    end
  end

  # Split `--- frontmatter --- body` into a Hash and the remaining Markdown body.
  def parse_frontmatter(raw)
    match = raw.match(/\A---\n(.*?)\n---\n?(.*)\z/m) or return [{}, raw]
    meta = match[1].split("\n").filter_map do |line|
      pair = line.match(/\A([\w-]+):\s*(.*)\z/) and [pair[1], pair[2].strip]
    end.to_h
    [meta, match[2]]
  end

  # `|` marks where the text may break: each piece is escaped, wrapped by the block and joined.
  def breakable(text, separator, &wrap)
    text.split('|').map { |part| wrap.call(Renderer.escape(part)) }.join(separator)
  end

  # What speakers wrote is shown as written: no curly quotes or dashes swapped in.
  def markdown_to_html(body)
    Kramdown::Document.new(
      body,
      input: 'GFM',
      auto_ids: false,
      smart_quotes: %w[apos apos quot quot],
      typographic_symbols: { hellip: '...', mdash: '---', ndash: '--', laquo: '<<', raquo: '>>', laquo_space: '<< ', raquo_space: ' >>' }
    ).to_html
  end

  def excerpt(html, limit)
    text = CGI.unescapeHTML(html.gsub(/<[^>]+>/, ' ')).gsub(/\s+/, ' ').strip
    text.length <= limit ? text : "#{text[0, limit]}…"
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
