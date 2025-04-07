# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/support/from_yaml_file"
require "time"

module ElasticGraph
  # The entry point into this library. Create an instance of this class to get access to
  # the public interfaces provided by this library.
  class Admin
    extend Support::FromYamlFile

    # @dynamic datastore_core, schema_artifacts
    attr_reader :datastore_core, :schema_artifacts

    # A factory method that builds an Admin instance from the given parsed YAML config.
    # `from_yaml_file(file_name, &block)` is also available (via `Support::FromYamlFile`).
    def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
      new(datastore_core: DatastoreCore.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block))
    end

    def initialize(datastore_core:, monotonic_clock: nil, clock: ::Time)
      @datastore_core = datastore_core
      @monotonic_clock = monotonic_clock
      @clock = clock
      @schema_artifacts = @datastore_core.schema_artifacts
    end

    def cluster_configurator
      @cluster_configurator ||= begin
        require "elastic_graph/admin/cluster_configurator"
        ClusterConfigurator.new(
          datastore_clients_by_name: @datastore_core.clients_by_name,
          index_defs: @datastore_core.index_definitions_by_name.values,
          index_configurations_by_name: schema_artifacts.indices,
          index_template_configurations_by_name: schema_artifacts.index_templates,
          scripts: schema_artifacts.datastore_scripts,
          cluster_settings_manager: cluster_settings_manager,
          clock: @clock
        )
      end
    end

    def cluster_settings_manager
      @cluster_settings_manager ||= begin
        require "elastic_graph/admin/cluster_configurator/cluster_settings_manager"
        ClusterConfigurator::ClusterSettingsManager.new(
          datastore_clients_by_name: @datastore_core.clients_by_name,
          datastore_config: @datastore_core.config,
          logger: @datastore_core.logger
        )
      end
    end

    def datastore_indexing_router
      @datastore_indexing_router ||= begin
        require "elastic_graph/indexer/datastore_indexing_router"
        Indexer::DatastoreIndexingRouter.new(
          datastore_clients_by_name: datastore_core.clients_by_name,
          mappings_by_index_def_name: schema_artifacts.index_mappings_by_index_def_name,
          monotonic_clock: monotonic_clock,
          logger: datastore_core.logger
        )
      end
    end

    def monotonic_clock
      @monotonic_clock ||= begin
        require "elastic_graph/support/monotonic_clock"
        Support::MonotonicClock.new
      end
    end

    # Returns an alternate `Admin` instance with the datastore clients replaced with
    # alternate implementations that turn all write operations into no-ops.
    def with_dry_run_datastore_clients
      require "elastic_graph/admin/datastore_client_dry_run_decorator"
      dry_run_clients_by_name = @datastore_core.clients_by_name.transform_values do |client|
        DatastoreClientDryRunDecorator.new(client)
      end

      Admin.new(datastore_core: DatastoreCore.new(
        config: datastore_core.config,
        logger: datastore_core.logger,
        schema_artifacts: datastore_core.schema_artifacts,
        clients_by_name: dry_run_clients_by_name,
        client_customization_block: datastore_core.client_customization_block
      ))
    end
  end
end
