# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/indexer/config"
require "elastic_graph/support/from_yaml_file"

module ElasticGraph
  class Indexer
    extend Support::FromYamlFile

    # @dynamic config, datastore_core, schema_artifacts, logger
    attr_reader :config, :datastore_core, :schema_artifacts, :logger

    # A factory method that builds an Indexer instance from the given parsed YAML config.
    # `from_yaml_file(file_name, &block)` is also available (via `Support::FromYamlFile`).
    def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      new(
        config: Indexer::Config.from_parsed_yaml(parsed_yaml),
        datastore_core: DatastoreCore.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      )
    end

    def initialize(
      config:,
      datastore_core:,
      datastore_router: nil,
      monotonic_clock: nil,
      clock: nil
    )
      @config = config
      @datastore_core = datastore_core
      @logger = datastore_core.logger
      @datastore_router = datastore_router
      @schema_artifacts = @datastore_core.schema_artifacts
      @monotonic_clock = monotonic_clock
      @clock = clock || ::Time
    end

    def datastore_router
      @datastore_router ||= begin
        require "elastic_graph/indexer/datastore_indexing_router"
        DatastoreIndexingRouter.new(
          datastore_clients_by_name: datastore_core.clients_by_name,
          mappings_by_index_def_name: schema_artifacts.index_mappings_by_index_def_name,
          monotonic_clock: monotonic_clock,
          logger: datastore_core.logger
        )
      end
    end

    def record_preparer_factory
      @record_preparer_factory ||= begin
        require "elastic_graph/indexer/record_preparer"
        RecordPreparer::Factory.new(schema_artifacts)
      end
    end

    def processor
      @processor ||= begin
        require "elastic_graph/indexer/processor"
        Processor.new(
          datastore_router: datastore_router,
          operation_factory: operation_factory,
          indexing_latency_slo_thresholds_by_timestamp_in_ms: config.latency_slo_thresholds_by_timestamp_in_ms,
          clock: @clock,
          logger: datastore_core.logger
        )
      end
    end

    def operation_factory
      @operation_factory ||= begin
        require "elastic_graph/indexer/operation/factory"
        Operation::Factory.new(
          schema_artifacts: schema_artifacts,
          index_definitions_by_graphql_type: datastore_core.index_definitions_by_graphql_type,
          record_preparer_factory: record_preparer_factory,
          logger: datastore_core.logger,
          skip_derived_indexing_type_updates: config.skip_derived_indexing_type_updates,
          configure_record_validator: nil
        )
      end
    end

    def monotonic_clock
      @monotonic_clock ||= begin
        require "elastic_graph/support/monotonic_clock"
        Support::MonotonicClock.new
      end
    end
  end
end
