# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "stringio"

module ElasticGraph
  # Runs specs against each ingestion format, so that everything we verify for JSON ingestion is also
  # verified for protobuf ingestion. Examples keep building events with the JSON-based factories and
  # pass them through `round_trip_indexing_events`, which publishes them in the format under test and
  # returns the events the indexer receives.
  module IngestionFormatSupport
    # Metadata for the examples of each ingestion format. Protobuf examples are pending until the indexer
    # can ingest protobuf events. RSpec still runs pending examples and fails any that pass, so once
    # protobuf ingestion works, this blanket `pending` gives way to `pending` metadata on the examples
    # that still expose gaps.
    METADATA_BY_FORMAT = {
      json: {},
      proto: {pending: "`elasticgraph-indexer` cannot ingest protobuf events yet."}
    }

    # The stock schema takes a couple of seconds to define, so we define it once per process.
    def self.proto_schema_artifacts
      @proto_schema_artifacts ||= yield
    end

    module ClassMethods
      # Defines a context for each ingestion format and evaluates the given block in each of them.
      # The block receives the format so that it can vary group-level definitions by format.
      def for_each_ingestion_format(&block)
        METADATA_BY_FORMAT.each do |format, metadata|
          context "with #{format} ingestion", **metadata do
            include_context "ingestion format support", format
            module_exec(format, &block)
          end
        end
      end
    end
  end

  RSpec.shared_context "ingestion format support" do |format|
    let(:ingestion_format) { format }

    let(:ingestion_schema_artifacts) do
      if ingestion_format == :json
        stock_schema_artifacts
      else
        IngestionFormatSupport.proto_schema_artifacts do
          # The stock schema also declares a JSON schema version (and `define_schema` adds the JSON ingestion
          # extension), so these artifacts support both formats. Protobuf examples publish protobuf events.
          define_schema(
            schema_element_name_form: :snake_case,
            extension_modules: [ProtoIngestion::SchemaDefinition::APIExtension],
            output: ::StringIO.new
          ) do |schema|
            schema.as_active_instance { load ::File.join(CommonSpecHelpers::REPO_ROOT, "config", "schema.rb") }
          end
        end
      end
    end

    # The schema definition extension modules for specs that dump their own schema artifacts. Unlike the stock
    # schema artifacts above, protobuf artifacts dumped this way support only protobuf ingestion.
    def ingestion_schema_definition_extension_modules
      if ingestion_format == :json
        json_ingestion_schema_definition_extension_modules
      else
        [ProtoIngestion::SchemaDefinition::APIExtension]
      end
    end

    # Publishes the given events in the ingestion format under test, returning the events the indexer receives.
    def round_trip_indexing_events(events)
      return events if ingestion_format == :json
      raise ::NotImplementedError, "Protobuf indexing events cannot be decoded yet."
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
  end

  RSpec.configure do |config|
    config.extend IngestionFormatSupport::ClassMethods
  end
end
