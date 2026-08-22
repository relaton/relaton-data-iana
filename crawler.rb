require 'fileutils'
require 'relaton/iana/data_fetcher'
require_relative 'index_builder'

# token = ARGV.shift

# Match only the generated `index-*` outputs (index-v1.yaml, index-v2.yaml and
# their zips) -- NOT the `index_builder.rb` source this crawler requires, which a
# bare `index*` glob would delete out from under the next run.
# spec/crawler_sources_spec.rb guards this.
FileUtils.rm(Dir.glob("index-*"))

def fast_fail_system(command)
  return if system(command)

  exit_status = $?.exitstatus || 1 # exit fails if $?.exitstatus is nil
  puts "Command '#{command}' failed with exit code #{exit_status}"
  exit exit_status
end

# Fail the crawl if the clone fails, rather than fetching against a missing or
# stale checkout. A silent no-op here would be invisible downstream: `data/` and
# the reference index would both come out short *together*, so the collision
# cross-check below would pass and publish the truncated result. The
# `unless Dir.exist?` guard is what makes fast-failing safe for a local rerun --
# a bare re-clone over an existing checkout exits 128. Delete the directory to
# force a fresh clone. spec/crawler_sources_spec.rb guards all this.
unless Dir.exist?("iana-registries")
  fast_fail_system("git clone https://github.com/ietf-tools/iana-registries.git iana-registries")
end

FileUtils.rm_rf("data")
# Writes the index of the day: index-v2.yaml once the pubid migration lands in
# the relaton gem, index-v1.yaml before it.
Relaton::Iana::DataFetcher.fetch

# index-v1 (the legacy string-keyed index): rebuilt here over the data/ tree,
# because every released relaton line still reads index-v1.zip from this branch.
# Same arrangement as relaton-data-bipm and relaton-data-ccsds.
#
# Zipping and committing are not done here -- relaton/support's shared
# crawler.yml zips every index*.yaml and commits both the yaml and the zip.
IanaIndexBuilder.build_index_v1
