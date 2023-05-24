require 'fileutils'
require 'relaton_iana'

# token = ARGV.shift

FileUtils.rm(Dir.glob("index*"))

system("git clone https://github.com/ietf-tools/iana-registries.git iana-registries")

FileUtils.rm_rf("data")
RelatonIana::DataFetcher.fetch

system "zip index-v1.zip index-v1.yaml"
system "git add index-v1.zip index-v1.yaml"
