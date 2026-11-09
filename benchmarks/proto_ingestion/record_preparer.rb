#!/usr/bin/env ruby
# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "bundler/setup"

require "benchmark/ips"
require "elastic_graph/indexer/event"
require "elastic_graph/proto_ingestion/record_preparer"
require "elastic_graph/schema_artifacts/from_disk"
require "elastic_graph/spec_support/proto_publisher"

artifacts = ElasticGraph::SchemaArtifacts::FromDisk.new(::File.expand_path("../../config/schema/artifacts", __dir__))
publisher = ElasticGraph::SpecSupport::ProtoPublisher.new(artifacts)
event = ElasticGraph::Indexer::Event.new(
  op: "upsert", type: "Component", id: "c1", version: 1,
  record: {
    "id" => "c1", "name" => "benchmark", "created_at" => "2024-02-29T12:34:56.123456789Z",
    "position" => {"x" => 1.5, "y" => 2.5}, "tags" => ["one", "two", "three"],
    "part_ids" => ["p1", "p2"], "owner_ids" => ["o1", "o2"]
  },
  schema_version: nil, ingestion_format: "proto"
)
native = publisher.round_trip(event).record.freeze
preparer = ElasticGraph::ProtoIngestion::RecordPreparer.new(artifacts)
expected = preparer.prepare_for_index("Component", native, nil)
raise "Timestamp preparation changed" unless expected.fetch("created_at") == "2024-02-29T12:34:56.123Z"

puts RUBY_DESCRIPTION
puts "Construction includes scalar preparers; cold preparation also compiles root and nested message plans."
puts "Warm preparation includes presence checks, nested objects, lists, and timestamp normalization."

Benchmark.ips do |benchmark|
  benchmark.config(time: 5, warmup: 2)
  benchmark.report("construct preparer") { ElasticGraph::ProtoIngestion::RecordPreparer.new(artifacts) }
  benchmark.report("cold preparation") do
    ElasticGraph::ProtoIngestion::RecordPreparer.new(artifacts).prepare_for_index("Component", native, nil)
  end
  benchmark.report("warm preparation") { preparer.prepare_for_index("Component", native, nil) }
  benchmark.compare!
end

# Keep protobuf's JSON conversion at scalar leaves; measure its share of preparation separately.
timestamp = native.created_at
date_time_preparer = artifacts.runtime_metadata.scalar_types_by_name.fetch("DateTime").load_indexing_preparer.extension_class

Benchmark.ips do |benchmark|
  benchmark.config(time: 5, warmup: 2)
  benchmark.report("timestamp leaf") do
    date_time_preparer.prepare_for_indexing(::JSON.parse(::Google::Protobuf.encode_json(timestamp)))
  end
  benchmark.report("complete record") { preparer.prepare_for_index("Component", native, nil) }
end
