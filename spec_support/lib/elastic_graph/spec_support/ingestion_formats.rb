# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/indexing_event_decoder"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/spec_support/compiled_proto_support"

RSpec.shared_context "ingestion format support" do |format|
  include ElasticGraph::ProtoIngestion::CompiledProtoSupport

  let(:ingestion_format) { format }
  let(:ingestion_schema_artifacts) do
    if format == :json
      stock_schema_artifacts
    else
      generate_schema_artifacts(extension_modules: [ElasticGraph::ProtoIngestion::SchemaDefinition::APIExtension]) do |schema|
        schema.as_active_instance { load File.join(ElasticGraph::CommonSpecHelpers::REPO_ROOT, "config/schema.rb") }
      end
    end
  end

  around do |example|
    if format == :json
      example.run
    else
      with_compiled_proto(ingestion_schema_artifacts) do |pool, path|
        @ingestion_proto_pool = pool
        @ingestion_proto_decoder = ElasticGraph::ProtoIngestion::IndexingEventDecoder.new(
          config: {"descriptor_set_file" => path}, schema_artifacts: ingestion_schema_artifacts, logger: Logger.new(StringIO.new)
        )
        @ingestion_proto_types = ElasticGraph::ProtoIngestion::RuntimeSchema.new(ingestion_schema_artifacts).types
        example.run
      end
    end
  end

  def round_trip_indexing_events(events)
    return events if ingestion_format == :json
    envelope_class = @ingestion_proto_pool.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass
    batch_class = @ingestion_proto_pool.lookup("elasticgraph.ElasticGraphEventBatch").msgclass
    envelopes = events.map do |event|
      type = event.fetch("type")
      field = "record_#{ElasticGraph::Support::Casing.to_upper_snake(type).downcase}"
      attributes = event.slice("op", "id", "version", "latency_timestamps")
      attributes[field] = proto_json_value(type, event.fetch("record"))
      envelope_class.decode_json(JSON.generate(attributes))
    end
    @ingestion_proto_decoder.decode(batch_class.encode(batch_class.new(events: envelopes)))
  end

  def proto_json_value(type, value)
    return nil if value.nil?
    type = type.delete_suffix("!")
    if type.start_with?("[")
      return value.map { |item| proto_json_value(type.delete_prefix("[").delete_suffix("]"), item) }
    end
    metadata = @ingestion_proto_types.fetch(type)
    if metadata["scalar"]
      return JSON.generate(value) if metadata.fetch("scalar") == "Untyped"
      return value
    end
    return metadata.fetch("enum_values").key(value) if metadata["enum_values"]
    if metadata["subtypes"]
      subtype = value.fetch("__typename")
      return {ElasticGraph::Support::Casing.to_upper_snake(subtype).downcase => proto_json_value(subtype, value)}
    end
    metadata.fetch("fields").to_h do |name, field|
      [name, proto_json_value(field.fetch("type"), value[name])]
    end
  end
end
