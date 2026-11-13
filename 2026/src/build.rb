# Builds the 2026 site into <out-dir>, to be served under <base> (e.g. /2026).
# Comment stripping is done via node (minify.mjs).
#
# Usage: ruby build.rb <out-dir> <base>

require 'fileutils'
require 'set'

Dir.chdir(__dir__)
require_relative 'blog_builder'
require_relative 'page_builder'

OUT = File.expand_path(ARGV[0] || abort('usage: ruby build.rb <out-dir> <base>'))
BASE = ARGV[1] || abort('usage: ruby build.rb <out-dir> <base>')
SITE = 'https://picorubykaigi.org'

EXCLUDE = Set.new(%w[
  tools sessions templates
  build.rb minify.mjs blog_builder.rb page_builder.rb renderer.rb
])

FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

Dir.children(__dir__).each do |entry|
  next if entry.start_with?('.') || EXCLUDE.include?(entry) || entry.end_with?('.md')

  FileUtils.cp_r(entry, File.join(OUT, entry))
end

FileUtils.rm_rf(File.join(OUT, 'blog', 'posts'))
Dir.glob(File.join(OUT, '**', '{*.md,.DS_Store}'), File::FNM_DOTMATCH).each { |f| FileUtils.rm_f(f) }

PageBuilder.new(OUT).build
BlogBuilder.new(OUT).build

Dir.glob(File.join(OUT, 'game', '*.rb')).each do |f|
  src = File.read(f).lines.reject { |l| l.match?(/\A\s*#/) }.join
  File.write(f, src.gsub(/\n{3,}/, "\n\n"))
end

# The sources link from the site root ("/schedule/", "https://picorubykaigi.org/images/..."). Put BASE
# in front of every such link that points at something this build wrote, so links to other sites on
# the same domain (e.g. /adventure-board/) stay as they are.
tops = Dir.children(OUT).map { |entry| Regexp.escape(entry) }.join('|')
ending = %q{(?=["'`)?#<\s])}
root_link = %r{(?<=["'`(])/(?=(?:#{tops})(?:/|#{ending}))}
site_link = %r{#{Regexp.escape(SITE)}/(?=(?:(?:#{tops})(?:/|#{ending}))|#{ending})}
Dir.glob(File.join(OUT, '**', '*.{html,css,js,rb}')).each do |file|
  text = File.read(file)
  text = text.gsub(root_link, "#{BASE}/").gsub(site_link, "#{SITE}#{BASE}/")
  text = text.gsub('href="/"', %(href="#{BASE}/")) if file.end_with?('.html')
  File.write(file, text)
end

unless system('node', 'minify.mjs', OUT)
  abort('minify.mjs failed')
end

puts "Built #{OUT}."
