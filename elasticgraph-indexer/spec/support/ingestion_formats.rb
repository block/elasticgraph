# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/spec_support/proto_publisher"

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

    module ProtoFormat
      include IngestionFormatSupport

      FORMAT = :proto
      METADATA = {ingests_proto_data: true}

      # The stock schema artifacts are dumped with the protobuf extension. Using them avoids re-loading `config/schema.rb`:
      # Ruby resets a file's coverage each time it is loaded, so a re-load would discard coverage from earlier loads.
      def ingestion_schema_artifacts
        stock_schema_artifacts
      end

      def ingestion_schema_definition_extension_modules
        [ProtoIngestion::SchemaDefinition::APIExtension]
      end

      # Capture publishers before another dump overwrites their schema and metadata.
      # These versions select test fixtures only; no version is placed on the protobuf wire.
      def capture_proto_publisher(version, schema_artifacts)
        (@proto_publishers_by_version ||= {})[version] = SpecSupport::ProtoPublisher.new(schema_artifacts)
      end

      def round_trip_indexing_events(events, schema_artifacts: ingestion_schema_artifacts)
        publisher = (@proto_publishers ||= {}.compare_by_identity)[schema_artifacts] ||= SpecSupport::ProtoPublisher.new(schema_artifacts)
        events.map do |event|
          historical_publisher = @proto_publishers_by_version&.fetch(event.schema_version) || publisher
          publisher.round_trip(event, publisher: historical_publisher)
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
