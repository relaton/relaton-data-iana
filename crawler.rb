require 'fileutils'
require 'relaton_iana'

ENV["GITHUB_TOKEN"] = ARGV.shift

FileUtils.rm_rf("data")
RelatonIana::DataFetcher.fetch
