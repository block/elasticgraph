# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "verify_indices"
require "elastic_graph/elasticsearch/client"

RSpec.describe FieldRetrievalIndexVerification do
  let(:expected) do
    {"mappings" => {"properties" => {"name" => {"type" => "keyword"}}},
     "settings" => {"index.mapping.coerce" => false, "index.mapping.ignore_malformed" => false}}
  end

  it "accepts unchanged scalar mappings and explicit harmless defaults" do
    physical = Marshal.load(Marshal.dump(expected))
    physical.fetch("mappings").fetch("properties").fetch("name").merge!("doc_values" => true, "store" => false)
    physical.fetch("mappings")["_source"] = {"enabled" => true}
    expect(described_class.problems(physical, expected, ["name"])).to eq []
  end

  it "rejects absent, disabled, transformed, ignored, or substituted field values" do
    [{}, {"type" => "long"}, {"type" => "keyword", "doc_values" => false},
      {"type" => "keyword", "normalizer" => "lowercase"}, {"type" => "keyword", "ignore_above" => 10},
      {"type" => "keyword", "null_value" => "missing"}].each do |mapping|
      actual = expected.merge("mappings" => {"properties" => {"name" => mapping}})
      expect(described_class.problems(actual, expected, ["name"])).to include("name: missing or incompatible physical mapping")
    end
  end

  it "rejects lost source, runtime shadowing, and incompatible effective index settings" do
    configurations = [
      expected.merge("mappings" => expected.fetch("mappings").merge("enabled" => false)),
      expected.merge("mappings" => expected.fetch("mappings").merge("_source" => {"enabled" => false})),
      expected.merge("mappings" => expected.fetch("mappings").merge("_source" => {"excludes" => ["name"]})),
      expected.merge("mappings" => expected.fetch("mappings").merge("runtime" => {"name" => {"type" => "keyword"}}))
    ]
    [{"index.max_docvalue_fields_search" => "99"}, {"index.mapping.coerce" => "true"},
      {"index.mapping.ignore_malformed" => "true"}, {"index.mapping.ignore_above" => "10"},
      {"index.mapping.source.mode" => "synthetic"}, {"index.derived_source.enabled" => "true"}].each do |overrides|
      configurations << expected.merge("settings" => expected.fetch("settings").merge(overrides))
    end
    configurations.each { |actual| expect(described_class.problems(actual, expected, ["name"])).not_to be_empty }
  end

  def core_for(rollover: true, fields: {"name" => true, "id" => true, "tags" => false}, names: ["things__old_suffix", "things__2026"])
    metadata = fields.transform_values { |eligible| double(doc_values_eligible: eligible) }
    index = double(name: "things", accessible_from_queries?: true, fields_by_path: metadata,
      cluster_to_query: "main", rollover_index_template?: rollover, index_expression_for_search: rollover ? "things__*" : "things")
    client = instance_double(ElasticGraph::Elasticsearch::Client)
    allow(client).to receive(:list_indices_matching).with(index.index_expression_for_search).and_return(names)
    allow(client).to receive(:get_index_template).with("things").and_return({"template" => expected}) if rollover
    names.each { |name| allow(client).to receive(:get_index).with(name).and_return(expected) }
    config = {"indices" => {"things" => expected}, "index_templates" => {"things" => {"template" => expected}}}
    core = double(schema_artifacts: double(datastore_config: config), index_definitions_by_name: {"things" => index}, clients_by_name: {"main" => client})
    [core, client]
  end

  it "reads every physical generation matching the search wildcard, including unknown rollover suffixes" do
    core, client = core_for
    expect(client).to receive(:get_index).with("things__old_suffix").and_return({})
    report = described_class.verify(core)

    expect(report.fetch("compatible")).to be false
    expect(report.fetch("data_parity_verified")).to be false
    expect(report.fetch("checks").map { |check| check.fetch("name") }).to eq ["things", "things__2026", "things__old_suffix"]
    expect(report.fetch("checks").last.fetch("problems")).not_to be_empty
  end

  it "checks ordinary indices without requiring a rollover template" do
    core, = core_for(rollover: false, names: ["things"])
    report = described_class.verify(core)
    expect(report.fetch("compatible")).to be true
    expect(report.fetch("checks").map { |check| check.fetch("eligible_fields") }).to eq [1]
  end

  it "does not certify an empty dataset or artifacts without eligible fields" do
    core, = core_for(names: [])
    expect(described_class.verify(core).fetch("compatible")).to be false
    core, = core_for(fields: {"name" => false})
    expect { described_class.verify(core) }.to raise_error(/No eligible payload fields/)
  end

  it "rejects invalid CLI arguments before connecting" do
    expect { described_class.run([]) }.to raise_error(ArgumentError, /Usage/)
    expect { described_class.run(["--settings", "settings.yaml", "extra"]) }.to raise_error(ArgumentError, /Usage/)
  end
end
