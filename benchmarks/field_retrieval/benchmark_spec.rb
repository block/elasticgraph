# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "benchmark"

RSpec.describe FieldRetrievalBenchmark do
  def response(source: {}, fields: {})
    {"_shards" => {"failed" => 0}, "hits" => {"hits" => [{"_index" => "test", "_id" => "1", "_source" => source, "fields" => fields}]}}
  end

  it "preserves false and zero and treats missing scalar values as null" do
    source = response(source: {"flag" => false, "count" => 0, "missing" => nil})
    alternate = response(fields: {"flag" => [false], "count" => [0]})
    fields = %w[flag count missing]
    expect(described_class.payload(alternate, fields, [])).to eq(described_class.payload(source, fields, fields))
  end

  it "rejects even singleton source lists rather than silently treating them as scalars" do
    expect { described_class.payload(response(source: {"tags" => ["a"]}), ["tags"], ["tags"]) }
      .to raise_error(/only direct scalars/)
    expect { described_class.payload(response(fields: {"tags" => ["a", "b"]}), ["tags"], []) }
      .to raise_error(/multiple values/)
  end

  it "does not time partial search results as successes" do
    expect { described_class.payload(response.merge("timed_out" => true), [], []) }.to raise_error(/timed out/)
    expect { described_class.payload(response.merge("_shards" => {"failed" => 1}), [], []) }.to raise_error(/failed shards/)
  end

  it "requires known mappings without value-changing options" do
    expect(described_class.eligible_mapping?({"type" => "keyword", "store" => true})).to be true
    [{"type" => "text"}, {"type" => "date"}, {"type" => "keyword", "doc_values" => false},
      {"type" => "keyword", "normalizer" => "lowercase"}, {"type" => "keyword", "ignore_above" => 10},
      {"type" => "long", "null_value" => 0}].each do |mapping|
      expect(described_class.eligible_mapping?(mapping)).to be false
    end
  end

  it "rejects unsafe or invalid options before connecting to a datastore" do
    expect(described_class::Client).not_to receive(:new)
    [["--index", "*", "--fields", "id"], ["--index", "test", "--fields", "object.id"],
      ["--iterations", "0"], ["--warmup", "-1"], ["--counts", "0"], ["--fields", "id"]].each do |arguments|
      expect { described_class.run(arguments) }.to raise_error(ArgumentError)
    end
  end

  it "aborts comparisons when an alternate retrieval path loses a value" do
    client = instance_double(described_class::Client)
    source = response(source: {"code" => "original"}).merge("took" => 1)
    alternate = response.merge("took" => 1)
    allow(client).to receive(:request) do |_, _, body|
      [body["_source"] ? source : alternate, 100]
    end
    runner = described_class::Runner.new(client, {seed: 1110, warmup: 0, iterations: 1})
    expect { runner.measure("test", ["code"], {"size" => 1}, stored: false) }.to raise_error(/Results differ/)
  end

  it "keeps existing-index mode read only and skips unavailable stored fields" do
    client = instance_double(described_class::Client)
    allow(client).to receive(:request).with("GET", "/").and_return([{"version" => {"number" => "test"}}, 1])
    allow(client).to receive(:request).with("GET", "/test/_mapping").and_return([
      {"test" => {"mappings" => {"properties" => {"code" => {"type" => "keyword"}}}}}, 1
    ])
    allow(client).to receive(:request).with("POST", "/test/_search?request_cache=false&preference=eg-retrieval-bench", anything).and_return([
      response(source: {"code" => "a"}, fields: {"code" => ["a"]}).merge("took" => 1), 100
    ])
    options = {index: "test", fields: ["code"], query: {"size" => 1}, seed: 1110, warmup: 0, iterations: 1}
    report = described_class::Runner.new(client, options).run
    expect(report.fetch("results").first.fetch("variants").keys).to contain_exactly("source", "fields", "docvalue_fields")
  end

  it "cleans up its own synthetic index when population fails" do
    client = instance_double(described_class::Client)
    allow(SecureRandom).to receive(:hex).with(8).and_return("fixture")
    expect(client).to receive(:request).with("PUT", "/eg-retrieval-bench-fixture", anything).ordered
    expect(client).to receive(:request).with("POST", "/eg-retrieval-bench-fixture/_bulk", anything).ordered.and_return([{"errors" => true}, 100])
    expect(client).to receive(:request).with("DELETE", "/eg-retrieval-bench-fixture").ordered
    runner = described_class::Runner.new(client, {seed: 1110, counts: [1], documents: 1})
    expect { runner.synthetic(10) }.to raise_error(/Bulk indexing failed/)
  end

  it "never deletes an index it could not create" do
    client = instance_double(described_class::Client)
    allow(SecureRandom).to receive(:hex).with(8).and_return("fixture")
    expect(client).to receive(:request).with("PUT", "/eg-retrieval-bench-fixture", anything).and_raise("Index already exists")
    expect(client).not_to receive(:request).with("DELETE", anything)
    runner = described_class::Runner.new(client, {seed: 1110, counts: [1], documents: 1})
    expect { runner.synthetic(10) }.to raise_error(/Index already exists/)
  end
end
