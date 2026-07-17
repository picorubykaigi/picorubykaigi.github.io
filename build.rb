# Builds the published site into dist/.
# Comment stripping is done via node (minify.mjs).

require 'fileutils'
require 'set'
require_relative 'blog_builder'

ROOT = Dir.pwd
OUT = File.join(ROOT, 'dist')

EXCLUDE = Set.new(%w[
  node_modules dist design tools
  package.json package-lock.json
  build.mjs build.rb minify.mjs blog_builder.rb Gemfile Gemfile.lock templates
])

FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

Dir.children(ROOT).each do |entry|
  next if entry.start_with?('.') || EXCLUDE.include?(entry) || entry.end_with?('.md')

  FileUtils.cp_r(File.join(ROOT, entry), File.join(OUT, entry))
end

FileUtils.rm_rf(File.join(OUT, 'blog', 'posts'))
Dir.glob(File.join(OUT, '**', '{*.md,.DS_Store}'), File::FNM_DOTMATCH).each { |f| FileUtils.rm_f(f) }

BlogBuilder.new(OUT).build

Dir.glob(File.join(OUT, 'game', '*.rb')).each do |f|
  src = File.read(f).lines.reject { |l| l.match?(/\A\s*#/) }.join
  File.write(f, src.gsub(/\n{3,}/, "\n\n"))
end

unless system('node', 'minify.mjs', OUT)
  abort('minify.mjs failed')
end

puts 'Built dist/.'
