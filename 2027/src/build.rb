# Builds the 2027 site into <out-dir>, to be served under <base>.
#
# Usage: ruby build.rb <out-dir> <base>

require 'fileutils'

out = File.expand_path(ARGV[0] || abort('usage: ruby build.rb <out-dir> <base>'))

FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)
FileUtils.cp(File.join(__dir__, 'index.html'), out)

puts "Built #{out}."
