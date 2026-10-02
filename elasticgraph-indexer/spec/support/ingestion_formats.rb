# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/proto_ingestion/indexing_event_decoder"
require "elastic_graph/proto_ingestion/ingestion_adapter"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/spec_support/compiled_proto_support"
require "json"

module ElasticGraph
  # Runs specs against each ingestion format, so that everything we verify for JSON ingestion is also
  # verified for protobuf ingestion. Examples keep building events with the JSON-based factories and
  # pass them through `round_trip_indexing_events`, which publishes them in the format under test and
  # returns the events the indexer receives.
  module IngestionFormatSupport
    module ClassMethods
      # Defines a context for each ingestion format and evaluates the given block in each of them.
      # The block receives the format so that it can vary group-level definitions by format.
      def for_each_ingestion_format(&block)
        [JSONFormat, ProtoFormat].each do |format_module|
          context "with #{format_module::FORMAT} ingestion", ingestion_format: format_module::FORMAT, **format_module::METADATA do
            # `prepend` so that `index_records` takes precedence over the `UsesDatastore` one, which RSpec defines on the group.
            prepend format_module

            module_exec(format_module::FORMAT, &block)
          end
        end
      end
    end

    def ingestion_format
      self.class::FORMAT
    end

    def indexer
      @indexer ||= build_indexer
    end

    def build_indexer(schema_artifacts: ingestion_schema_artifacts, **options, &customize_datastore_config)
      super
    end

    def process_indexing_events(events, via: indexer)
      via.processor.process(round_trip_indexing_events(events, schema_artifacts: via.schema_artifacts), refresh_indices: true)
    end

    # Overrides the `UsesDatastore` helper so that records are indexed via the ingestion format under test.
    def index_records(*records)
      events = Indexer::TestSupport::Converters.upsert_events_for_records(records)
      process_indexing_events(events)
      events
    end

    module JSONFormat
      include IngestionFormatSupport

      FORMAT = :json
      METADATA = {ingests_json_data: true}

      def ingestion_schema_artifacts
        stock_schema_artifacts
      end

      # The schema definition extension modules for specs that dump their own schema artifacts.
      def ingestion_schema_definition_extension_modules
        json_ingestion_schema_definition_extension_modules
      end

      # Publishes the given events in this ingestion format, returning the events the indexer receives.
      def round_trip_indexing_events(events, schema_artifacts: ingestion_schema_artifacts)
        events
      end
    end

    # A publisher compiled from its own snapshot, independently of the current decoder/converter.
    class ProtoPublisher
      def initialize(pool, schema_artifacts)
        @pool = pool
        config = schema_artifacts.runtime_metadata.indexer_extension_modules.find do |extension|
          extension.extension_ref.fetch("name") == "ElasticGraph::ProtoIngestion::IndexerExtension"
        end.extension_ref.fetch("config")
        @package = config.fetch("package_name")
        @type_names = config.fetch("types", {})
        @field_overrides = config.fetch("fields", {})
        @envelope = pool.lookup("#{@package}.ElasticGraphEventEnvelope")
        @schema = ProtoIngestion::RuntimeSchema.new(schema_artifacts)
        @envelope.lookup_oneof("record").each { |field| @schema.register(field.subtype) }
      end

      def encode(event)
        record_field = @envelope.lookup_oneof("record").find do |field|
          public_type_name(field.subtype) == event.type
        end
        attributes = {
          "op" => event.op, "id" => event.id, "version" => event.version,
          "latency_timestamps" => event.latency_timestamps,
          record_field.name => proto_json_value(event.type, event.record, nil)
        }
        envelope = @envelope.msgclass.decode_json(::JSON.generate(attributes))
        batch_class = @pool.lookup("#{@package}.ElasticGraphEventBatch").msgclass
        batch_class.encode(batch_class.new(events: [envelope]))
      end

      private

      def public_type_name(descriptor)
        proto_name = descriptor.name.delete_prefix("#{@package}.")
        @type_names.fetch(proto_name, proto_name)
      end

      def proto_json_value(type, value, field)
        type = type.delete_suffix("!")
        if type.start_with?("[")
          item_type = type.delete_prefix("[").delete_suffix("]")
          if item_type.start_with?("[")
            return value.map { |item| {"values" => proto_json_value(item_type, item, field.subtype.lookup("values"))} }
          end
          return value.map { |item| proto_json_value(item_type, item, field) }
        end
        metadata = @schema.types.fetch(type)
        if metadata["scalar"]
          return ::JSON.generate(value) if metadata.fetch("scalar") == "Untyped"
          return value
        end
        return metadata.fetch("enum_values").key(value) || value if metadata["enum_values"]
        proto_name = @type_names.key(type) || type
        descriptor = @pool.lookup("#{@package}.#{proto_name}")
        if metadata["subtypes"]
          subtype = value.fetch("__typename")
          alternative = descriptor.lookup_oneof("value").find { |entry| public_type_name(entry.subtype) == subtype }
          return {alternative.name => proto_json_value(subtype, value, nil)}
        end
        overrides = @field_overrides.fetch(proto_name, {})
        descriptor.filter_map do |entry|
          name = overrides.fetch(entry.name, {}).fetch("public_name", entry.name)
          next unless value.key?(name) && !value[name].nil?
          [entry.name, proto_json_value(metadata.fetch("fields").fetch(name).fetch("type"), value.fetch(name), entry)]
        end.to_h
      end
    end

    module ProtoFormat
      include IngestionFormatSupport

      FORMAT = :proto
      METADATA = {ingests_proto_data: true}

      # The stock schema takes a couple of seconds to define, so we define it once per process.
      def self.stock_schema_artifacts
        @stock_schema_artifacts ||= yield
      end

      def ingestion_schema_artifacts
        ProtoFormat.stock_schema_artifacts do
          generate_schema_artifacts(extension_modules: ingestion_schema_definition_extension_modules) do |schema|
            schema.as_active_instance { load ::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema.rb") }
          end
        end
      end

      def ingestion_schema_definition_extension_modules
        [ProtoIngestion::SchemaDefinition::APIExtension]
      end

      include ProtoIngestion::CompiledProtoSupport

      # Snapshots the publisher's compiled contract before the next dump replaces its artifacts.
      # The version is test-only state, never a field in the protobuf event.
      def capture_proto_publisher(version, schema_artifacts)
        (@proto_publishers ||= {})[version] = compile_proto_contract(schema_artifacts)
      end

      def round_trip_indexing_events(events, schema_artifacts: ingestion_schema_artifacts)
        contract = (@proto_contracts ||= {}.compare_by_identity)[schema_artifacts] ||= compile_proto_contract(schema_artifacts)
        decoded = events.flat_map do |event|
          publisher = @proto_publishers ? @proto_publishers.fetch(event.schema_version) : contract
          contract.fetch(:decoder).decode(publisher.fetch(:publisher).encode(event))
        end
        converted, failures = contract.fetch(:adapter).events_from(decoded)
        expect(failures).to be_empty
        converted
      end

      def compile_proto_contract(schema_artifacts)
        source = if schema_artifacts.respond_to?(:proto_schema)
          schema_artifacts.proto_schema
        else
          ::File.read(::File.join(schema_artifacts.artifacts_dir, "schema.proto"))
        end
        results = ::Data.define(:proto_schema).new(source)
        with_compiled_proto(results) do |pool, path|
          {
            publisher: ProtoPublisher.new(pool, schema_artifacts),
            decoder: ProtoIngestion::IndexingEventDecoder.new(config: {"descriptor_set_file" => path}, schema_artifacts: schema_artifacts),
            adapter: ProtoIngestion::IngestionAdapter.new(schema_artifacts: schema_artifacts)
          }
        end
      end
    end
  end

  RSpec.configure do |config|
    config.extend IngestionFormatSupport::ClassMethods, :ingests_data

    config.before(:example, :ingests_data) do |ex|
      expect(ex.metadata).to include(:ingestion_format),
        "Indexer integration and acceptance specs must wrap their examples in `for_each_ingestion_format`."
    end
  end
end
