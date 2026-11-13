# Builds the published site into dist/: each year under dist/<year>/, and CNAME at the root.
# A year with <year>/site/ is a finished year and is copied as it is; otherwise <year>/src/build.rb builds it.
#
# Usage: ruby build.rb [year ...]   # no year: every year

require 'fileutils'
require 'rbconfig'

ROOT = __dir__
OUT = File.join(ROOT, 'dist')

all_years = Dir.children(ROOT).grep(/\A\d{4}\z/).sort
years = ARGV.empty? ? all_years : ARGV
(years - all_years).each { |year| abort("no such year: #{year}") }

FileUtils.rm_rf(OUT) if ARGV.empty?

# Until the old URLs (/schedule/ and so on) redirect to /2026/, keep serving the 2026 site at the
# root too. Its build empties the output directory, so it goes first. Remove once the redirect is live.
if ARGV.empty?
  system(RbConfig.ruby, File.join(ROOT, '2026', 'src', 'build.rb'), OUT, '') || abort('2026 build at the root failed')
end

FileUtils.mkdir_p(OUT)
FileUtils.cp(File.join(ROOT, 'CNAME'), OUT)

years.each do |year|
  out = File.join(OUT, year)
  site = File.join(ROOT, year, 'site')
  if Dir.exist?(site)
    FileUtils.rm_rf(out)
    FileUtils.cp_r(site, out)
    puts "Copied #{year}/site."
  else
    system(RbConfig.ruby, File.join(ROOT, year, 'src', 'build.rb'), out, "/#{year}") || abort("#{year} build failed")
  end
end
