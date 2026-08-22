require 'kramdown'
require 'kramdown-parser-gfm'
require 'fileutils'
require 'cgi'
require 'uri'
require 'date'
require 'erb'
require_relative 'renderer'

# Generates the blog (post pages + index) from blog/posts/*.md into <out>/blog.
# Usage: ruby blog_builder.rb <out-dir>
class BlogBuilder
  SITE = 'https://picorubykaigi.org'
  TEMPLATES = File.join(__dir__, 'templates')
  HEADER = Renderer.partial('header.html.erb')
  TWEET_URL = %r{https?://(?:twitter\.com|x\.com)/\w+/status/\d+(?:\?\S*)?}
  DANCERS = '<div class="blog-dancers" aria-hidden="true">' +
            ('<div class="blog-dancer"><span class="blog-dancer-led"></span></div>' * 4) +
            '</div>'

  def initialize(out_dir)
    @out_dir = out_dir
  end

  def build
    posts_src = File.join(Dir.pwd, 'blog', 'posts')
    out_blog = File.join(@out_dir, 'blog')
    FileUtils.mkdir_p(out_blog)

    filenames = Dir.exist?(posts_src) ? Dir.children(posts_src).select { |name| name.end_with?('.md') } : []
    posts = filenames.map do |filename|
      meta, body = parse_frontmatter(File.read(File.join(posts_src, filename)))
      slug = slug_of(filename)
      content_html = markdown_to_html(expand_tweet_urls(body))
      content_html = content_html.gsub(/<hr\s*\/?>/, DANCERS)   # 水平線は dancers
      description = meta['description']
      description = excerpt(content_html) if description.to_s.empty?
      {
        slug: slug,
        title: meta['title'] || slug,
        date: meta['date'] || '',
        description: description,
        content_html: content_html,
        og_image: og_image_for(content_html, slug),
        has_tweet: content_html.include?('twitter-tweet')
      }
    end

    # Newest first.
    posts.sort_by! { |post| post[:date].to_s }.reverse!

    show_back_link = posts.length > 1
    posts.each do |post|
      File.write(File.join(out_blog, "#{post[:slug]}.html"), post_page(post, show_back_link))
    end
    File.write(File.join(out_blog, 'index.html'), index_page(posts))

    posts.length
  end

  private

  # Split `--- frontmatter --- body` into a Hash and the remaining Markdown body.
  def parse_frontmatter(raw)
    m = raw.match(/\A---\n(.*?)\n---\n?(.*)\z/m)
    return [{}, raw] unless m

    meta = {}
    m[1].split("\n").each do |line|
      if (kv = line.match(/\A([\w-]+):\s*(.*)\z/))
        meta[kv[1]] = kv[2].strip
      end
    end
    [meta, m[2]]
  end

  def escape(text)
    CGI.escapeHTML(text.to_s)
  end

  def display_date(date)
    Date.iso8601(date.to_s).strftime('%Y.%m.%d.')
  end

  def slug_of(filename)
    File.basename(filename, '.md').sub(/\A\d{4}-\d{2}-\d{2}-/, '')
  end

  # OGP image: the body's first image (as an absolute URL), or the site default.
  def og_image_for(content_html, slug)
    if (m = content_html.match(/<img\b[^>]*?\bsrc="([^"]+)"/i))
      URI.join("#{SITE}/blog/#{slug}.html", m[1]).to_s
    else
      "#{SITE}/images/ogp.png"
    end
  end

  # Wrap a run of standalone tweet URLs (blank lines allowed between them) in one
  # .tweet-embed block, so consecutive tweets read as a single group.
  def expand_tweet_urls(body)
    run = /^[ \t]*#{TWEET_URL}[ \t]*(?:\n+[ \t]*#{TWEET_URL}[ \t]*)*$/
    body.gsub(run) do |match|
      embeds = match.scan(TWEET_URL).map do |url|
        %(<blockquote class="twitter-tweet" data-dnt="true"><a href="#{url}">#{url}</a></blockquote>)
      end.join
      %(<div class="tweet-embed">#{embeds}</div>)
    end
  end

  def markdown_to_html(body)
    Kramdown::Document.new(body, input: 'GFM', syntax_highlighter: nil, auto_ids: false).to_html
  end

  # First `limit` characters of the body text, for the meta/OG description.
  def excerpt(content_html, limit = 200)
    text = CGI.unescapeHTML(content_html.gsub(/<[^>]+>/, ' ')).gsub(/\s+/, ' ').strip
    text.length > limit ? "#{text[0, limit]}…" : text
  end

  # templates

  # Render templates/<name> with the given locals. Templates may call the helpers
  # above (escape, display_date) and reference SITE.
  def render(name, **locals)
    b = binding
    locals.each { |key, value| b.local_variable_set(key, value) }
    ERB.new(File.read(File.join(TEMPLATES, name)), trim_mode: '-').result(b)
  end

  def post_page(post, show_back_link)
    render('post.html.erb', post: post, show_back_link: show_back_link, header: HEADER.chomp)
  end

  def index_page(posts)
    render('index.html.erb', posts: posts, header: HEADER.chomp)
  end
end

if $PROGRAM_NAME == __FILE__
  out_dir = ARGV[0] || abort('usage: ruby blog_builder.rb <out-dir>')
  count = BlogBuilder.new(out_dir).build
  puts "Generated #{count} blog page(s)."
end
