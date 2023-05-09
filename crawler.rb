require 'fileutils'
require 'relaton_iana'

# ENV["GITHUB_TOKEN"] = ARGV.shift

system("git clone --dept 1 git@github.com:ietf-tools/iana-registries.git")

FileUtils.rm_rf("data")
RelatonIana::DataFetcher.fetch
