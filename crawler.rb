require 'fileutils'
require 'relaton_iana'

FileUtils.rm_rf("data")
RelatonIana::DataFetcher.fetch
