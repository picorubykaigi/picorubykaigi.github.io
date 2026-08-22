#!/usr/bin/env ruby
#
# 開発用サーバ。dist/ を配信しつつ、ソースの変更を見張って差分だけ dist/ に反映する。
#
#   bundle exec ruby tools/dev.rb [port]   # 既定 8916

require 'webrick'
require 'fileutils'
require 'rbconfig'

$stdout.sync = true

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)
OUT = File.join(ROOT, 'dist')

PORT = (ARGV[0] || ENV['PORT'] || 8916).to_i
INTERVAL = 0.4
IGNORE = %w[dist node_modules design tools docs .git .cloudflare].freeze
REBUILD_ALL = %w[build.rb blog_builder.rb minify.mjs].freeze
NOT_COPIED = %w[package.json package-lock.json Gemfile Gemfile.lock build.mjs].freeze

def blog_source?(path)
  path.start_with?('blog/posts/', 'templates/')
end

def classify(path)
  return :full if REBUILD_ALL.include?(path)
  return :blog if blog_source?(path)
  return :skip if NOT_COPIED.include?(path) || path.end_with?('.md')

  :copy
end

def source_files
  Dir.glob('**/*').reject do |path|
    IGNORE.any? { |dir| path == dir || path.start_with?("#{dir}/") } || File.directory?(path)
  end
end

def snapshot
  source_files.to_h { |path| [path, File.mtime(path)] }
rescue Errno::ENOENT
  retry   # 監視中に消えたファイルがあれば取り直す
end

def build_blog
  system(RbConfig.ruby, File.join(ROOT, 'blog_builder.rb'), OUT) || warn('blog_builder.rb failed')
end

def full_build
  system(RbConfig.ruby, File.join(ROOT, 'build.rb')) || warn('build.rb failed')
end

def copy_to_dist(path)
  dest = File.join(OUT, path)
  FileUtils.mkdir_p(File.dirname(dest))
  FileUtils.cp(path, dest)
end

def apply(changed, removed)
  kinds = changed.map { |path| classify(path) }

  if removed.any? || kinds.include?(:full)
    reason = removed.any? ? '削除あり' : 'ビルド定義の変更'
    print "  (#{reason} → フルビルド) "
    return full_build
  end

  changed.zip(kinds).each { |path, kind| copy_to_dist(path) if kind == :copy }
  build_blog if kinds.include?(:blog)
  true
end

server = WEBrick::HTTPServer.new(
  Port: PORT,
  BindAddress: '0.0.0.0',
  Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
  AccessLog: []
)

no_cache = Class.new(WEBrick::HTTPServlet::FileHandler) do
  def do_GET(req, res)
    super
    res['Cache-Control'] = 'no-store'
  end
end
server.mount('/', no_cache, OUT, FancyIndexing: true)

devtools_probe = Class.new(WEBrick::HTTPServlet::AbstractServlet) do
  def do_GET(_req, res)
    res.status = 404
    res.body = ''
  end
end
server.mount('/.well-known/appspecific/com.chrome.devtools.json', devtools_probe)

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }

puts 'Building...'
full_build

watcher = Thread.new do
  previous = snapshot
  loop do
    sleep INTERVAL
    current = snapshot
    changed = current.reject { |path, mtime| previous[path] == mtime }.keys
    removed = previous.keys - current.keys
    previous = current
    next if changed.empty? && removed.empty?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    print "#{Time.now.strftime('%H:%M:%S')} #{(changed + removed).join(' ')} "
    apply(changed, removed)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    puts "(#{elapsed}ms)"
  end
end

puts "http://127.0.0.1:#{PORT}/"
puts 'Stop to Ctrl-C'
server.start
watcher.kill
