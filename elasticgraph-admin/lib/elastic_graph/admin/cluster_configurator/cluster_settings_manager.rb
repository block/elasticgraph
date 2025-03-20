# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class Admin
    class ClusterConfigurator
      # Responsible for updating datastore cluster settings based on the mode EG is in, maintenance mode or indexing mode
      class ClusterSettingsManager
        def initialize(datastore_clients_by_name:, datastore_config:, logger:)
          @datastore_clients_by_name = datastore_clients_by_name
          @datastore_config = datastore_config
          @logger = logger
        end

        # Starts index maintenance mode, if it has not already been started. This method is idempotent.
        #
        # In index maintenance mode, you can safely delete or update the index configuration without
        # worrying about indices being auto-created with dynamic mappings (e.g. due to an indexing
        # race condition). While in this mode, indexing operations on documents that fall into new rollover
        # indices may fail since the auto-creation of those indices is disabled.
        #
        # `cluster_spec` can be the name of a specific cluster (as a string) or `:all_clusters`.
        def start_index_maintenance_mode!(cluster_spec)
          cluster_names_for(cluster_spec).each do |cluster_name|
            datastore_client_named(cluster_name).put_persistent_cluster_settings(desired_cluster_settings(cluster_name))
          end
        end

        # Ends index maintenance mode, if it has not already ended. This method is idempotent.
        #
        # Outside of this mode, you cannot safely delete or update the index configuration. However,
        # new rollover indices will correctly be auto-created as documents that fall in new months or
        # years are indexed.
        #
        # `cluster_spec` can be the name of a specific cluster (as a string) or `:all_clusters`.
        def end_index_maintenance_mode!(cluster_spec)
          cluster_names_for(cluster_spec).each do |cluster_name|
            datastore_client_named(cluster_name).put_persistent_cluster_settings(
              desired_cluster_settings(cluster_name, auto_create_index_patterns: ["*#{ROLLOVER_INDEX_INFIX_MARKER}*"])
            )
          end
        end

        # Runs a block in index maintenance mode. Should be used to wrap any code that updates your index configuration.
        #
        # `cluster_spec` can be the name of a specific cluster (as a string) or `:all_clusters`.
        def in_index_maintenance_mode(cluster_spec)
          start_index_maintenance_mode!(cluster_spec)

          begin
            yield
          rescue => e
            @logger.warn "WARNING: ClusterSettingsManager#in_index_maintenance_mode is not able to exit index maintenance mode due to exception #{e}.\n A bit of manual cleanup may be required (although a re-try should be idempotent)."
            raise # re-raise the same error
          else
            # Note: we intentionally do not end maintenance mode in an `ensure` block, because if an exception
            # happens while we `yield`, we do _not_ want to exit maintenance mode. Exiting maintenance mode
            # could put us in a state where indices are dynamically created when we do not want them to be.
            end_index_maintenance_mode!(cluster_spec)
          end
        end

        private

        def desired_cluster_settings(cluster_name, auto_create_index_patterns: [])
          {
            # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-index_.html#index-creation
            #
            # We generally want to disable automatic index creation in order to require all indices to be properly
            # defined and configured. However, we must allow kibana to create some indices for it to be usable
            # (https://discuss.elastic.co/t/elasticsearchs-action-auto-create-index-setting-impact-on-kibana/117701).
            "action.auto_create_index" => ([".kibana*"] + auto_create_index_patterns).map { |p| "+#{p}" }.join(",")
          }.merge(@datastore_config.clusters.fetch(cluster_name).settings)
        end

        def datastore_client_named(cluster_name)
          @datastore_clients_by_name.fetch(cluster_name) do
            raise Errors::ClusterOperationError,
              "Unknown datastore cluster name: `#{cluster_name}`. Valid cluster names: #{@datastore_clients_by_name.keys}"
          end
        end

        def cluster_names_for(cluster_spec)
          case cluster_spec
          when :all_clusters then @datastore_clients_by_name.keys
          else [cluster_spec]
          end
        end
      end
    end
  end
end
