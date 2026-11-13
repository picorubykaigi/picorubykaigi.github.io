#!/usr/bin/env ruby
#
# 開発用サーバ。dist/ を配信しつつ、その年のソース(<年>/src)の変更を見張って、その年を dist/<年>/ にビルドし直す。
# 年を省くと、src/ がある年のうち最新の年。
#
#   bundle exec ruby tools/dev.rb [port] [year]   # 既定 8916

require 'webrick'
require 'rbconfig'

$stdout.sync = true

ROOT = File.expand_path('..', __dir__)
OUT = File.join(ROOT, 'dist')

PORT = (ARGV[0] || ENV['PORT'] || 8916).to_i
YEAR = ARGV[1] || Dir.children(ROOT).grep(/\A\d{4}\z/).select { |year| Dir.exist?(File.join(ROOT, year, 'src')) }.max
SRC = File.join(ROOT, YEAR, 'src')
INTERVAL = 0.4

def snapshot
  Dir.glob('**/*', base: SRC).reject { |path| File.directory?(File.join(SRC, path)) }
     .to_h { |path| [path, File.mtime(File.join(SRC, path))] }
rescue Errno::ENOENT
  retry   # 監視中に消えたファイルがあれば取り直す
end

def build
  system(RbConfig.ruby, File.join(ROOT, 'build.rb'), YEAR, out: File::NULL) || warn('build.rb failed')
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
# 画像生成ページ(<年>/src/tools/ogp*.html)も同じサーバから見られるようにする。<base href="../"> の
# 参照先(images/ fonts/)は dist/<年>/ 側で解決される。
server.mount("/#{YEAR}/tools", no_cache, File.join(SRC, 'tools'), FancyIndexing: true)

devtools_probe = Class.new(WEBrick::HTTPServlet::AbstractServlet) do
  def do_GET(_req, res)
    res.status = 404
    res.body = ''
  end
end
server.mount('/.well-known/appspecific/com.chrome.devtools.json', devtools_probe)

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }

puts "Building #{YEAR}..."
build

watcher = Thread.new do
  previous = snapshot
  loop do
    sleep INTERVAL
    current = snapshot
    changed = current.reject { |path, mtime| previous[path] == mtime }.keys + (previous.keys - current.keys)
    previous = current
    next if changed.empty?

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    print "#{Time.now.strftime('%H:%M:%S')} #{changed.join(' ')} "
    build
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    puts "(#{elapsed}ms)"
  end
end

puts "http://127.0.0.1:#{PORT}/#{YEAR}/"
puts 'Stop to Ctrl-C'
server.start
watcher.kill
