# frozen_string_literal: true

# crawler.rb clones repositories and fetches on load, so it cannot be required.
# Read it as source text instead, the way relaton-data-bipm guards its own.
RSpec.describe "crawler.rb" do
  let(:source) { File.read(File.join(REPO_ROOT, "crawler.rb")) }

  # A bare `index*` glob also matches index_builder.rb and would delete the very
  # file the crawler requires. relaton-data-bipm hit this exact bug.
  it "removes only the generated index-* outputs, not index_builder.rb" do
    globs = source.scan(/Dir\.glob\(["']([^"']+)["']\)/).flatten
    expect(globs).not_to be_empty
    globs.each do |glob|
      expect(File.fnmatch(glob, "index_builder.rb")).to be(false),
                                                        "glob #{glob.inspect} matches index_builder.rb"
      expect(File.fnmatch(glob, "index-v1.yaml")).to be(true)
    end
  end

  # A bare `system("git clone ...")` returns false and falls through, so the
  # fetch would run against a missing or stale checkout -- and data/ plus the
  # reference index would then come out short together, which the collision
  # cross-check cannot see. relaton-data-bipm guards its clones the same way.
  it "fast-fails the clone, and guards it for a local rerun" do
    expect(source).to match(/fast_fail_system\(["']git clone /)
    expect(source).not_to match(/^\s*system\(["']git clone /)
    expect(source).to match(/unless Dir\.exist\?\(["']iana-registries["']\)/)
  end

  it "builds index-v1 after the fetch" do
    fetch = source.index("Relaton::Iana::DataFetcher.fetch")
    build = source.index("IanaIndexBuilder.build_index_v1")
    expect(fetch).not_to be_nil
    expect(build).not_to be_nil
    expect(build).to be > fetch
  end
end
