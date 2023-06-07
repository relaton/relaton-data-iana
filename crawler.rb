require 'fileutils'
require 'relaton_iana'

# token = ARGV.shift

FileUtils.rm(Dir.glob("index*"))

system("git clone https://github.com/ietf-tools/iana-registries.git iana-registries")

FileUtils.rm_rf("data")
RelatonIana::DataFetcher.fetch
