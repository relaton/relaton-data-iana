require 'fileutils'
require 'relaton/iana/data_fetcher'

# token = ARGV.shift

FileUtils.rm(Dir.glob("index*"))

# system("git clone https://github.com/ietf-tools/iana-registries.git iana-registries")

FileUtils.rm_rf("data")
Relaton::Iana::DataFetcher.fetch
