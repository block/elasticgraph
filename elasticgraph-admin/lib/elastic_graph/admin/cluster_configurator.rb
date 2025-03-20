# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/cluster_configurator/script_configurator"
require "elastic_graph/admin/index_definition_configurator"
require "elastic_graph/errors"
require "stringio"

module ElasticGraph
  class Admin
    # Facade responsible for overall cluster configuration. Delegates to other classes as
    # necessary to configure different aspects of the cluster (such as index configuration,
    # cluster settings, etc).
    class ClusterConfigurator
      def initialize(
        datastore_clients_by_name:,
        index_defs:,
        index_configurations_by_name:,
        index_template_configurations_by_name:,
        scripts:,
        cluster_settings_manager:,
        clock:
      )
        @datastore_clients_by_name = datastore_clients_by_name
        @index_defs = index_defs
        @index_configurations_by_name = index_configurations_by_name.merge(index_template_configurations_by_name)
        @scripts_by_id = scripts
        @cluster_settings_manager = cluster_settings_manager
        @clock = clock
      end

      # Attempts to configure all aspects of the datastore cluster. Known/expected failure
      # cases are pre-validated so that an error can be raised before applying any changes to
      # any indices, so that we hopefully don't wind up in a "partially configured" state.
      def configure_cluster(output)
        # Note: we do not want to cache `index_configurators_for` here in a variable, because it's important
        # for our tests that different instances are used for `validate` vs `configure!`. That's the case because
        # each `index_configurator` memoizes some datastore responses (e.g. when it fetches the settings or
        # mappings for an index...). In our tests, we use different datastore clients that connect to the same
        # datastore server, and that means that when we reuse the same `index_configurator`, the datastore
        # index winds up being mutated (via another client) in between `validate` and `configure!` breaking assumptions
        # of the datastore response memoization. By using different index configurators for the two steps it
        # avoids some odd bugs.
        script_configurators = script_configurators_for(output)

        errors = script_configurators.flat_map(&:validate) + index_definition_configurators_for(output).flat_map(&:validate)

        if errors.any?
          error_descriptions = errors.map.with_index do |error, index|
            "#{index + 1}): #{error}"
          end.join("\n#{"=" * 80}\n\n")

          raise Errors::ClusterOperationError, "Got #{errors.size} validation error(s):\n\n#{error_descriptions}"
        end

        script_configurators.each(&:configure!)

        @cluster_settings_manager.in_index_maintenance_mode(:all_clusters) do
          index_definition_configurators_for(output).each(&:configure!)
        end
      end

      def accessible_index_definitions
        @accessible_index_definitions ||= @index_defs.reject { |i| i.all_accessible_cluster_names.empty? }
      end

      private

      def script_configurators_for(output)
        # It's a bit tricky to know which datastore cluster a script is needed in (the script metadata
        # doesn't store that), but storing a script in a cluster that doesn't need it causes no harm. The
        # id of each script contains the hash of its contents so there's no possibility of different clusters
        # needing a script with the same `id` to have different contents. So here we create a script configurator
        # for each datastore client.
        @datastore_clients_by_name.values.flat_map do |datastore_client|
          @scripts_by_id.map do |id, payload|
            ScriptConfigurator.new(
              datastore_client: datastore_client,
              script_context: payload.fetch("context"),
              script_id: id,
              script: payload.fetch("script"),
              output: output
            )
          end
        end
      end

      def index_definition_configurators_for(output)
        @index_defs.flat_map do |index_def|
          env_agnostic_config = @index_configurations_by_name.fetch(index_def.name)

          index_def.all_accessible_cluster_names.map do |cluster_name|
            IndexDefinitionConfigurator.new(@datastore_clients_by_name.fetch(cluster_name), index_def, env_agnostic_config, output, @clock)
          end
        end
      end
    end
  end
end
