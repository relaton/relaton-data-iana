# frozen_string_literal: true

source 'https://rubygems.org'

# `relaton-iana` no longer exists as its own gem -- the IANA flavor lives in the
# combined `relaton` gem (relaton/relaton, gemspec at repo root). `crawler.rb`'s
# `require "relaton/iana/data_fetcher"` is the correct path there.
#
# Pin `main` explicitly, for the reason relaton-data-bipm documents: an unpinned
# `github:` freezes whatever branch was current into Gemfile.lock, and relaton's
# remote churns many transient feature branches, so a later `bundle update` can
# fail fetching a branch that has since been deleted.
gem 'relaton', git: 'https://github.com/relaton/relaton.git', branch: 'main'

# Temporary: pin pubid to `main`. The published pubid gem (2.0.0.pre.alpha.9)
# predates `Pubid::Iana::Identifiers::Registry#number`, the key the IANA
# index-v2 is built on, and a git gem's gemspec (relaton's) cannot carry a git
# source -- so bundler would otherwise resolve the stale published pubid. Remove
# once pubid publishes a release carrying that attribute.
#
# `pubid/pubid`, not `metanorma/pubid`: the repo was renamed. GitHub still
# redirects the old path, but a redirect only lasts until someone creates a new
# repo at the old name -- at which point the pin would silently resolve to a
# different repository instead of failing.
gem 'pubid', github: 'pubid/pubid', branch: 'main'

group :test do
  gem 'rspec', '~> 3.13'
end
