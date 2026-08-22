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

  # Reference ids that no data file carries -- ids lost to a filename collision.
  #
  # @param [Array<Hash>] rows .rows output, `{ id:, file: }` hashes
  # @param [Array<String>] ids .reference_ids output, plain id strings
  def shadowed_ids(rows, ids)
    ids - rows.map { |row| row[:id] }
  end

  # Rebuild INDEX_V1 from the data/ tree.
  #
  # Raises when a reference id has no data file of its own.
  # `Relaton::Core::DataFetcher#output_file` collapses `/` and `-` to the same
  # character, so `rpki/signed-objects` and `rpki-signed-objects` both map to
  # `data/rpki-signed-objects.yaml`; `Relaton::Iana::DataFetcher#save_doc`
  # detects the clash, warns, and then overwrites instead of disambiguating, so
  # the first document is gone and its id is unbuildable from data/. That is a
  # relaton bug, not something to route around here -- see the hand-off
  # relaton__relaton__iana-output-file-collision.md.
  def build_index_v1(file: INDEX_V1, glob: DATA_GLOB, reference_files: REFERENCE_FILES)
    # Read the reference before writing: it may BE `file` (pre-migration gem).
    reference = reference_rows(files: reference_files)
    data_rows = rows(glob: glob)
    check_shadowed! data_rows, reference

    File.write file, data_rows.to_yaml
    puts "index-v1: wrote #{data_rows.size} entries to #{file}"
    data_rows
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

  def check_shadowed!(data_rows, reference)
    by_id = reference.to_h { |row| [row[:id], row[:file]] }
    shadowed = shadowed_ids(data_rows, by_id.keys)
    return if shadowed.empty?

    detail = shadowed.map { |id| "  #{id} -> #{by_id[id]}" }.join("\n")
    raise Error, "index-v1: #{shadowed.size} id(s) have no data file of their " \
                 "own -- distinct docnumbers collided on one filename and " \
                 "Relaton::Iana::DataFetcher#save_doc overwrote instead of " \
                 "disambiguating:\n#{detail}\nFix the collision in the relaton " \
                 "gem, then re-run the crawl."
  end
end
