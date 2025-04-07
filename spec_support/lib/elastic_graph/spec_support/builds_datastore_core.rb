# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/datastore_core/config"
require "elastic_graph/schema_artifacts/from_disk"
require "elastic_graph/spec_support/graphql_profiling_logger_decorator"
require "elastic_graph/spec_support/stub_datastore_client"
require "stringio"

module ElasticGraph
  module BuildsDatastoreCore
    def build_datastore_core(
      client_customization_block: nil,
      clients_by_name: nil,
      config: nil,
      logger: nil,
      schema_definition: nil,
      schema_element_name_form: :snake_case,
      schema_element_name_overrides: {},
      derived_type_name_formats: {},
      enum_value_overrides_by_type: {},
      index_definitions: nil,
      clusters: nil,
      schema_artifacts_directory: nil,
      schema_artifacts: nil,
      datastore_backend: nil,
      reload_schema_artifacts: false,
      **config_overrides,
      &customize_config
    )
      config ||= begin
        yaml_config = parsed_test_settings_yaml
        if datastore_backend
          clusters_with_overrides =
            yaml_config.fetch("datastore").fetch("clusters").transform_values do |cluster_config|
              cluster_config.merge("backend" => datastore_backend.to_s)
            end

          yaml_config = yaml_config.merge(
            "datastore" => yaml_config.fetch("datastore").merge(
              "clusters" => clusters_with_overrides
            )
          )
        end

        DatastoreCore::Config.from_parsed_yaml(yaml_config).with(**config_overrides)
      end

      schema_artifacts ||=
        if schema_definition || schema_element_name_form != :snake_case || schema_element_name_overrides.any? || derived_type_name_formats.any?
          generate_schema_artifacts(
            schema_element_name_form: schema_element_name_form,
            schema_element_name_overrides: schema_element_name_overrides,
            derived_type_name_formats: derived_type_name_formats,
            enum_value_overrides_by_type: enum_value_overrides_by_type,
            reload_schema_artifacts: reload_schema_artifacts,
            &schema_definition
          )
        elsif schema_artifacts_directory
          # Deal with the relative nature of paths in config, ensuring we can run the specs while being
          # in the repo root and also while being in a gem directory.
          SchemaArtifacts::FromDisk.new(schema_artifacts_directory.sub("config", "#{CommonSpecHelpers::REPO_ROOT}/config"))
        else
          stock_schema_artifacts
        end

      if clients_by_name.nil? && respond_to?(:stubbed_datastore_client)
        client = datastore_client # a memoized instance of stubbed_datastore_client
        clients_by_name = {"main" => client, "other1" => client, "other2" => client, "other3" => client}
      end

      # We want the datastore to be as fast as possible in tests, and don't care about data durability.
      # To that end, we configure some settings here that attempt to optimize speed but sacrifice
      # durability (the data shouldn't hit disk, for example).
      optimal_test_setting_overrides = {
        "translog.durability" => "async",
        "translog.sync_interval" => "999999d", # effectively never
        "translog.flush_threshold_size" => "8gb", # effectively never
        "number_of_replicas" => 0
      }

      # We require an index definition for every index, so here we can provide one for *any*
      # index created by a test by using a hash with a default proc, which lazily provides
      # default configuration on demand. Individual tests can still provide their own index
      # definitions as desired.
      if index_definitions
        config = config.with(index_definitions: index_definitions)
      else
        original_index_defs = config.index_definitions

        config = config.with(index_definitions: Hash.new do |hash, index_def_name|
          hash[index_def_name] = config_index_def_of(
            query_cluster: "main",
            index_into_clusters: ["main"],
            ignore_routing_values: [],
            setting_overrides: optimal_test_setting_overrides
          )
        end)

        # Merge the optimal test settings into our original definitions.
        original_index_defs.each do |index_name, index_config|
          config.index_definitions[index_name] = index_config.with(
            setting_overrides: optimal_test_setting_overrides,
            setting_overrides_by_timestamp: index_config.setting_overrides_by_timestamp.transform_values do |overrides|
              optimal_test_setting_overrides.merge(overrides)
            end,
            custom_timestamp_ranges: index_config.custom_timestamp_ranges.map do |range|
              range.with(setting_overrides: optimal_test_setting_overrides.merge(range.setting_overrides))
            end
          )
        end
      end

      config = config.with(clusters: clusters) if clusters
      config = customize_config.call(config) if customize_config

      # If clients_by_name is specified, remove any entries from the config that *aren't* present.
      config = config.with(clusters: config.clusters.select { |it| clients_by_name.key?(it) }) if clients_by_name

      DatastoreCore.new(
        schema_artifacts: schema_artifacts,
        config: config,
        logger: GraphQLProfilingLoggerDecorator.maybe_wrap(logger || Logger.new(StringIO.new)),
        client_customization_block: client_customization_block,
        clients_by_name: clients_by_name
      )
    end
  end

  RSpec.configure do |c|
    c.include BuildsDatastoreCore, :builds_datastore_core
  end
end
