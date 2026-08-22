# frozen_string_literal: true

# Behaviour of the index-v1 builder the crawler runs after the fetch. These
# exercise the real builder over throwaway corpora; no network, no fetch.
RSpec.describe IanaIndexBuilder do
  describe ".rows" do
    it "returns symbol-keyed rows in sorted glob order" do
      in_workdir("data/b.yaml" => doc("bravo"),
                 "data/a.yaml" => doc("alpha/one")) do
        expect(described_class.rows).to eq(
          [{ id: "alpha/one", file: "data/a.yaml" },
           { id: "bravo", file: "data/b.yaml" }],
        )
      end
    end

    it "warns and skips a data file with no docnumber" do
      in_workdir("data/a.yaml" => doc("alpha"),
                 "data/broken.yaml" => { "docidentifier" => [] }) do
        rows = nil
        expect { rows = described_class.rows }
          .to output(/data\/broken\.yaml/).to_stderr
        expect(rows).to eq([{ id: "alpha", file: "data/a.yaml" }])
      end
    end

    it "warns and skips an unparseable data file rather than aborting" do
      in_workdir("data/a.yaml" => doc("alpha"),
                 "data/bad.yaml" => "docnumber: [unterminated\n") do
        rows = nil
        expect { rows = described_class.rows }
          .to output(/data\/bad\.yaml: Psych/).to_stderr
        expect(rows).to eq([{ id: "alpha", file: "data/a.yaml" }])
      end
    end

    # Psych parses the whole document tree, so a date anywhere in the file --
    # not only in docnumber -- decides whether the load succeeds.
    it "reads a document carrying an unquoted date" do
      in_workdir("data/a.yaml" => "docnumber: alpha\ndate:\n- at: 2024-01-26\n") do
        expect(described_class.rows).to eq([{ id: "alpha", file: "data/a.yaml" }])
      end
    end
  end

  describe ".reference_ids" do
    it "joins a v2 row to number/sub_registry, or to bare number" do
      in_workdir("index-v2.yaml" => [v2_row("rpki", nil, "data/rpki.yaml"),
                                     v2_row("rpki", "signed-objects", "data/x.yaml")]) do
        expect(described_class.reference_ids).to eq(["rpki", "rpki/signed-objects"])
      end
    end

    it "reads a v1 row's string id as-is" do
      in_workdir("index-v1.yaml" => [{ id: "rpki/signed-objects", file: "data/x.yaml" }]) do
        expect(described_class.reference_ids).to eq(["rpki/signed-objects"])
      end
    end

    it "prefers index-v2.yaml over index-v1.yaml" do
      in_workdir("index-v2.yaml" => [v2_row("from-v2", nil, "data/a.yaml")],
                 "index-v1.yaml" => [{ id: "from-v1", file: "data/a.yaml" }]) do
        expect(described_class.reference_ids).to eq(["from-v2"])
      end
    end

    # The hand-off's named failure mode: a stale pre-`number` row deserializes
    # with number nil and no error, silently bucketing every row together.
    it "raises on a v2 row with an empty or missing number" do
      in_workdir("index-v2.yaml" => [{ id: { "_type" => "pubid:iana:registry",
                                             "sub_registry" => "orphan" },
                                       file: "data/x.yaml" }]) do
        expect { described_class.reference_ids }
          .to raise_error(described_class::Error, /Regenerate the index/)
      end
    end

    it "raises on a row id that is neither a string nor a hash" do
      in_workdir("index-v1.yaml" => [{ id: 42, file: "data/x.yaml" }]) do
        expect { described_class.reference_ids }
          .to raise_error(described_class::Error, /unexpected row id/)
      end
    end

    it "raises when no reference index exists" do
      in_workdir("data/a.yaml" => doc("alpha")) do
        expect { described_class.reference_ids }
          .to raise_error(described_class::Error, /index-v2\.yaml/)
      end
    end
  end

  describe ".build_index_v1" do
    it "writes the data/ rows for a corpus with no collision" do
      in_workdir("data/a.yaml" => doc("alpha"),
                 "data/b.yaml" => doc("alpha/one"),
                 "index-v2.yaml" => [v2_row("alpha", nil, "data/a.yaml"),
                                     v2_row("alpha", "one", "data/b.yaml")]) do
        described_class.build_index_v1
        expect(YAML.safe_load_file("index-v1.yaml", permitted_classes: [Symbol]))
          .to eq([{ id: "alpha", file: "data/a.yaml" },
                  { id: "alpha/one", file: "data/b.yaml" }])
      end
    end

    # A data/ walk sees one docnumber per file, so a shadowed id is invisible to
    # it. The reference index is what makes the loss detectable.
    it "raises naming the shadowed id, and leaves index-v1.yaml untouched" do
      existing = [{ id: "rpki/signed-objects", file: "data/rpki-signed-objects.yaml" },
                  { id: "rpki-signed-objects", file: "data/rpki-signed-objects.yaml" }]
      in_workdir("data/rpki-signed-objects.yaml" => doc("rpki-signed-objects"),
                 "index-v1.yaml" => existing) do
        expect { described_class.build_index_v1 }
          .to raise_error(described_class::Error, %r{rpki/signed-objects})
        expect(YAML.safe_load_file("index-v1.yaml", permitted_classes: [Symbol]))
          .to eq(existing)
      end
    end
  end

  # Guard against this repo's real committed corpus, which still carries the
  # pre-fix crawl: `rpki/signed-objects` and `rpki-signed-objects` both mapped to
  # data/rpki-signed-objects.yaml through Core::DataFetcher#output_file, and
  # Iana::DataFetcher#save_doc overwrote instead of disambiguating, so the first
  # id has no file of its own -- 3405 index rows over 3404 files.
  #
  # relaton has since fixed this (Core::DataFetcher#unique_output_file), and a
  # crawl on the current gem produces 3405 files with no shadowed id. The
  # committed corpus does not change until that crawl is COMMITTED here, which
  # is what flips this spec, not the gem fix on its own.
  #
  # WHEN THE NEXT CRAWL LANDS, THIS SPEC GOES RED. Change the expectation to
  # `be_empty` then; it is what proves the regenerated corpus is whole.
  describe "the committed corpus" do
    it "shadows exactly one id, the pre-fix relaton output_file collision" do
      Dir.chdir(REPO_ROOT) do
        rows = described_class.rows
        expect(described_class.shadowed_ids(rows, described_class.reference_ids))
          .to eq(["rpki/signed-objects"])
      end
    end
  end
end
