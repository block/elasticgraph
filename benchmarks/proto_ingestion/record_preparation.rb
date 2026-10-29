# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

# Run from the repository root:
# bundle exec ruby -Ispec_support/lib benchmarks/proto_ingestion/record_preparation.rb

require "benchmark"
require "elastic_graph/indexer/event"
require "elastic_graph/indexer/record_preparer"
require "elastic_graph/proto_ingestion/record_preparer"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/test_support"
require "elastic_graph/spec_support/proto_publisher"

# Original converter from a2fd13432, retained here as a fixed benchmark baseline.
# Keeping it local makes the benchmark runnable after the PR is squashed and its branch deleted.
class LegacyRecordConverter
  def initialize(schema)
    @schema = schema
    @types = schema.types
  end

  def convert(type_name, message)
    metadata = @types.fetch(type_name)
    if metadata["subtypes"]
      variant = message.class.descriptor.lookup_oneof("value").find { |field| field.has?(message) }
      return nil unless variant
      subtype = variant.subtype.name.delete_prefix("#{@schema.package_name}.")
      return convert(subtype, variant.get(message)).merge("__typename" => subtype)
    end

    metadata.fetch("fields").filter_map do |name, field_metadata|
      field = message.class.descriptor.lookup(name)
      next if field.label != :repeated && !field.has?(message)
      converted = convert_typed_value(field_metadata.fetch("type"), field.get(message), field)
      [name, converted]
    end.to_h
  end

  private

  def convert_typed_value(type, value, field)
    return convert_value(type, value, field) unless type.start_with?("[")
    if value.class.respond_to?(:descriptor)
      field = value.class.descriptor.lookup("values")
      value = field.get(value)
    end
    item_type = type.delete_prefix("[").delete_suffix("]")
    value.map { |item| convert_typed_value(item_type, item, field) }
  end

  def convert_value(type_name, value, field)
    metadata = @types.fetch(type_name)
    if (enum_values = metadata["enum_values"])
      return nil if value == 0 || field.subtype.enummodule.lookup(0) == value
      return enum_values.fetch(value.to_s, value)
    end
    return convert(type_name, value) unless metadata["scalar"]
    return JSON.parse(value) if metadata.fetch("scalar") == "Untyped"
    return JSON.parse(Google::Protobuf.encode_json(value)) if field.type == :message
    value
  end
end

artifacts = ElasticGraph::SchemaDefinition::TestSupport.define_schema(
  schema_element_name_form: :snake_case,
  extension_modules: [ElasticGraph::ProtoIngestion::SchemaDefinition::APIExtension]
) do |schema|
  schema.enum_type("Status") { |type| type.values "ACTIVE", "onHold" }
  schema.object_type("Attachment") do |type|
    type.field "label", "String", name_in_index: "private_label"
    type.field "size", "LongString"
  end
  schema.object_type("Product") do |type|
    type.field "id", "ID!"
    type.field "name", "String", name_in_index: "private_name"
    type.field "active", "Boolean"
    type.field "large", "LongString"
    type.field "status", "Status"
    type.field "at", "DateTime"
    type.field "payload", "Untyped"
    type.field("attachments", "[Attachment]") { |field| field.mapping type: "object" }
    type.field "grid", "[[Int]]"
    type.index "products"
  end
end
publisher = ElasticGraph::SpecSupport::ProtoPublisher.new(artifacts)
event = ElasticGraph::Indexer::Event.new(
  op: "upsert", type: "Product", id: "p1", version: 1, schema_version: nil, ingestion_format: "proto",
  record: {"id" => "p1", "name" => "sample", "active" => false, "large" => 2**63 - 1, "status" => "onHold",
           "at" => "2024-02-29T12:34:56.123Z", "payload" => {"b" => [1, false, nil], "a" => 2},
           "attachments" => Array.new(8) { |i| {"label" => "file-#{i}", "size" => 2**53 + i} }, "grid" => [[1, 2], [], [3]]}
)
message = publisher.round_trip(event).record
metadata = ElasticGraph::ProtoIngestion::RuntimeMetadata::Schema.from_schema_artifacts(artifacts)
legacy_types = metadata.types_by_name.transform_values do |type|
  if type.scalar
    {"scalar" => type.scalar}
  elsif !type.enum_values_by_name.empty?
    {"enum_values" => type.enum_values_by_name}
  elsif !type.subtypes_by_field_name.empty?
    {"subtypes" => type.subtypes_by_field_name.values}
  else
    {"fields" => type.fields_by_name.transform_values { |field| {"type" => field.type.delete("!"), "name_in_index" => field.name_in_index} }}
  end
end
# Both paths use the same generated schema, native message, and shared scalar preparers.
# Descriptor registration, decoding, and preparer construction are outside the measured loop.
converter = LegacyRecordConverter.new(Data.define(:types, :package_name).new(legacy_types, metadata.package_name))
types = metadata.types_by_name.filter_map do |name, type|
  next if type.fields_by_name.empty?
  fields = type.fields_by_name.transform_values do |field|
    ElasticGraph::Indexer::RecordPreparer::FieldMetadata.new(type: field.type, name_in_index: field.name_in_index)
  end
  ElasticGraph::Indexer::RecordPreparer::TypeMetadata.new(name: name, fields_by_name: fields)
end
scalar_preparers = artifacts.runtime_metadata.scalar_types_by_name.transform_values { |scalar| scalar.load_indexing_preparer.extension_class }
shared = ElasticGraph::Indexer::RecordPreparer.new(scalar_preparers, types)
native = ElasticGraph::ProtoIngestion::RecordPreparer.new(artifacts)
paths = {
  "old conversion + shared preparation" => -> { shared.prepare_for_index("Product", converter.convert("Product", message), {}) },
  "native preparation" => -> { native.prepare_for_index("Product", message, {}) }
}
raise "Outputs differ" unless paths.values.map(&:call).uniq.size == 1
iterations = Integer(ENV.fetch("ITERATIONS", "20000"))
paths.each do |name, prepare|
  1_000.times { prepare.call }
  GC.start
  allocated_before = GC.stat(:total_allocated_objects)
  elapsed = Benchmark.realtime { iterations.times { prepare.call } }
  allocations = GC.stat(:total_allocated_objects) - allocated_before
  puts "#{name}: #{elapsed.round(3)}s; #{(iterations / elapsed).round} records/s; #{allocations.fdiv(iterations).round(1)} objects/record"
end
puts "Ruby #{RUBY_VERSION}; google-protobuf #{Gem.loaded_specs.fetch("google-protobuf").version}; #{iterations} iterations; decode and initialization excluded"
