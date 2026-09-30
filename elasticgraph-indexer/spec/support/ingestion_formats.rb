# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"

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

    def indexer
      @indexer ||= build_indexer
    end

    def build_indexer(schema_artifacts: ingestion_schema_artifacts, **options, &customize_datastore_config)
      super
    end

    def process_indexing_events(events, via: indexer)
      via.processor.process(round_trip_indexing_events(events), refresh_indices: true)
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
      def round_trip_indexing_events(events)
        events
      end
    end

    module ProtoFormat
      include IngestionFormatSupport

      FORMAT = :proto
      # Protobuf examples are pending until the indexer can ingest protobuf events. RSpec still runs pending
      # examples and fails any that pass, so once protobuf ingestion works, this blanket `pending` gives way
      # to `pending` metadata on the examples that still expose gaps.
      METADATA = {ingests_proto_data: true, pending: "`elasticgraph-indexer` cannot ingest protobuf events yet."}

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

      # simplecov:disable -- the indexer has no protobuf ingestion adapter yet, so it fails before it calls this.
      def round_trip_indexing_events(events)
        raise ::NotImplementedError, "Protobuf indexing events cannot be decoded yet."
      end
      # simplecov:enable
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
