# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"

require_relative "../index_builder"

# Absolute path to the repo root, so a spec can reach the real committed corpus
# (`data/`, `index-v1.yaml`) from inside an `in_workdir` chdir.
REPO_ROOT = File.expand_path("..", __dir__)

module WorkdirHelper
  # Run the block in a throwaway directory seeded with +files+, so the builder's
  # CWD-relative `data/**/*.yaml` glob and its `index-*.yaml` writes never touch
  # the repo. A Hash value is dumped as YAML; a String is written verbatim.
  def in_workdir(files = {})
    Dir.mktmpdir do |dir|
      files.each do |path, content|
        full = File.join(dir, path)
        FileUtils.mkdir_p File.dirname(full)
        File.write full, content.is_a?(String) ? content : content.to_yaml
      end
      Dir.chdir(dir) { yield dir }
    end
  end

  # A minimal data/ document: the builder reads only `docnumber`.
  def doc(docnumber)
    { "docnumber" => docnumber,
      "docidentifier" => [{ "content" => "IANA #{docnumber}", "primary" => true }] }
  end

  # One `index-v2.yaml` row for +number+ (+ optional +sub_registry+), in the
  # shape `Relaton::Index` writes for a `Pubid::Iana::Identifier`.
  def v2_row(number, sub_registry, file)
    id = { "_type" => "pubid:iana:registry", "number" => number }
    id["sub_registry"] = sub_registry if sub_registry
    { id: id, file: file }
  end
end

RSpec.configure do |config|
  config.include WorkdirHelper
  config.disable_monkey_patching!
end
