# frozen_string_literal: true

require "date"
require "yaml"

# Builds the legacy `index-v1.yaml` this repository publishes.
#
# The `relaton` gem's `Relaton::Iana::DataFetcher` writes only the index of the
# day -- `index-v2` once the pubid migration lands, `index-v1` before it. Every
# released `relaton` line still reads `index-v1.zip` from this repo's `v2`
# branch, so the crawler keeps producing it here. relaton-data-bipm and
# relaton-data-ccsds carry the same arrangement.
#
# The rows are rebuilt from the `data/` tree rather than transformed out of
# `index-v2.yaml`: reading each document's `docnumber` string keeps this
# independent of which index the gem happens to write, and of the gem's
# data model. Only `docnumber` is read -- no bibitem deserialization -- so
# data-model drift cannot break the build.
#
# A `data/` walk sees one docnumber per file, though, and two docnumbers can
# collide on one filename (see .build_index_v1). The index the fetch just wrote
# is therefore used as the authoritative id set to detect that loss.
module IanaIndexBuilder
  Error = Class.new(StandardError)

  DATA_GLOB = "data/**/*.yaml"
  INDEX_V1 = "index-v1.yaml"
  # index-v2 first: once the gem migrates it is the only index the fetch writes.
  # index-v1 is the fallback for the pre-migration gem, which still writes it.
  REFERENCE_FILES = %w[index-v2.yaml index-v1.yaml].freeze

  module_function

  # The index-v1 rows: `{ id: <docnumber>, file: <path> }` in sorted glob order.
  # A document with no `docnumber` is warned about and skipped; the reference
  # cross-check in .build_index_v1 turns that into a hard failure.
  def rows(glob: DATA_GLOB)
    Dir[glob].sort.filter_map do |file|
      docnumber = docnumber(file)
      # `warn` returns nil, which filter_map drops.
      next warn("index-v1: skipping #{file}: no docnumber") if docnumber.to_s.empty?

      { id: docnumber, file: file }
    rescue StandardError => e
      # One unreadable document must not abort the rebuild, as in
      # relaton-data-ccsds's build_index_v1.rb. The reference cross-check in
      # .build_index_v1 turns the resulting gap into a hard failure that names
      # the lost id, which is more use than a raw parse error here.
      warn "index-v1: skipping #{file}: #{e.class}: #{e.message}"
    end
  end

  # The authoritative `{ id => file }` pairs, from the first reference index
  # that exists.
  def reference_rows(files: REFERENCE_FILES)
    file = files.find { |f| File.exist? f }
    raise Error, "no reference index found (looked for #{files.join ', '}); " \
                 "did Relaton::Iana::DataFetcher.fetch run?" unless file

    load_index(file).map { |row| { id: reference_id(row[:id], file), file: row[:file] } }
  end

  # Just the ids of .reference_rows.
  def reference_ids(files: REFERENCE_FILES)
    reference_rows(files: files).map { |row| row[:id] }
  end

  # Reference rows whose file the crawl did not produce. Since the gem's
  # `unique_output_file` a filename collision is disambiguated, and since
  # relaton-iana#8/#9 a record-less registry's id deliberately ALIASES the
  # record-bearing document's file, so a shared file is the design. A file
  # the crawl never wrote is the only real loss.
  #
  # @param [Array<Hash>] data_rows .rows output, `{ id:, file: }` hashes
  # @param [Array<Hash>] reference .reference_rows output
  def lost_rows(data_rows, reference)
    data_files = data_rows.map { |row| row[:file] }
    reference.reject { |row| data_files.include?(row[:file]) }
  end

  # Reference ids the data tree carries only through another document's file:
  # the fetcher's aliases for record-less registries (relaton-iana#8, #9).
  # index-v1 carries them too, so a released-v2 consumer resolves either
  # spelling to the same document.
  #
  # @param [Array<Hash>] data_rows .rows output
  # @param [Array<Hash>] reference .reference_rows output
  # @return [Array<Hash>] rows to append to the rebuilt index
  def alias_rows(data_rows, reference)
    data_ids = data_rows.map { |row| row[:id] }
    data_files = data_rows.map { |row| row[:file] }
    reference.reject { |row| data_ids.include?(row[:id]) }
             .select { |row| data_files.include?(row[:file]) }
  end

  # Rebuild INDEX_V1 from the data/ tree.
  #
  # Raises when a reference id names a data file the crawl did not produce
  # (an id lost to the crawl, not an alias); alias ids -- shared files by
  # design -- are carried into the rebuilt index.
  def build_index_v1(file: INDEX_V1, glob: DATA_GLOB, reference_files: REFERENCE_FILES)
    # Read the reference before writing: it may BE `file` (pre-migration gem).
    reference = reference_rows(files: reference_files)
    data_rows = rows(glob: glob)
    check_lost! data_rows, reference

    rows = data_rows + alias_rows(data_rows, reference)
    File.write file, rows.to_yaml
    puts "index-v1: wrote #{rows.size} entries to #{file}"
    rows
  end

  # -- internals ------------------------------------------------------------

  # Read only the `docnumber` string, never the whole bibliographic item, so
  # data-model drift in the relaton gem cannot break the rebuild.
  #
  # Psych still parses the entire document tree, so Date/Time are permitted:
  # every date in the corpus is a quoted string today, but one unquoted date in
  # one upstream registry would otherwise raise Psych::DisallowedClass.
  def docnumber(file)
    doc = YAML.safe_load_file(file, permitted_classes: [Date, Time])
    doc["docnumber"] if doc.is_a? Hash
  end

  def load_index(file)
    YAML.safe_load(File.read(file), permitted_classes: [Symbol])
  end

  # A v1 row's id is the slug string itself; a v2 row's is the pubid hash, whose
  # slug is `number` joined to the optional `sub_registry`.
  def reference_id(id, file)
    return id if id.is_a? String
    raise Error, "#{file}: unexpected row id #{id.inspect}" unless id.is_a? Hash

    number = id["number"].to_s
    if number.empty?
      raise Error, "#{file}: row #{id.inspect} has no number -- a stale " \
                   "pre-`number` row deserializes silently as nil. " \
                   "Regenerate the index."
    end

    id["sub_registry"] ? "#{number}/#{id['sub_registry']}" : number
  end

  def check_lost!(data_rows, reference)
    lost = lost_rows(data_rows, reference)
    return if lost.empty?

    detail = lost.map { |row| "  #{row[:id]} -> #{row[:file]}" }.join("\n")
    raise Error, "index-v1: #{lost.size} reference id(s) name data files the " \
                 "crawl did not produce:\n#{detail}\nThe ids are lost, not " \
                 "aliases -- diagnose the crawl, then re-run it."
  end
end
