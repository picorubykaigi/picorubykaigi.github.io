# Builds the published site into dist/.
# Comment stripping is done via node (minify.mjs).

require 'fileutils'
require 'set'

ROOT = Dir.pwd
OUT = File.join(ROOT, 'dist')

EXCLUDE = Set.new(%w[
  node_modules dist design tools
  package.json package-lock.json
  build.mjs build.rb minify.mjs
])

FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

Dir.children(ROOT).each do |entry|
  next if entry.start_with?('.') || EXCLUDE.include?(entry) || entry.end_with?('.md')

  FileUtils.cp_r(File.join(ROOT, entry), File.join(OUT, entry))
end

Dir.glob(File.join(OUT, '**', '.DS_Store'), File::FNM_DOTMATCH).each { |f| FileUtils.rm_f(f) }

unless system('node', 'minify.mjs', OUT)
  abort('minify.mjs failed')
end

puts 'Built dist/.'
