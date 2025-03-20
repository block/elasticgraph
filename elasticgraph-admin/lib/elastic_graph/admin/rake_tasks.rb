# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/support/from_yaml_file"
require "rake/tasklib"

module ElasticGraph
  class Admin
    class RakeTasks < ::Rake::TaskLib
      extend Support::FromYamlFile::ForRakeTasks.new(ElasticGraph::Admin)

      attr_reader :output, :prototype_index_names

      def initialize(prototype_index_names: [], output: $stdout, &load_admin)
        @output = output
        @prototype_index_names = prototype_index_names.to_set
        @load_admin = load_admin

        define_tasks
      end

      private

      def define_tasks
        namespace :clusters do
          namespace :configure do
            desc "Performs the configuration of datastore clusters, including indices, settings, and scripts"
            task :perform do
              print_in_color "#{"=" * 80}\nNOTE: Performing datastore cluster updates for real!\n#{"=" * 80}", RED_COLOR_CODE

              index_defs = update_clusters_for(admin)
              output.puts "Finished updating datastore clusters. Validating index consistency..."
              admin.datastore_indexing_router.validate_mapping_completeness_of!(:all_accessible_cluster_names, *index_defs)
              output.puts "Done."
            end

            desc "Dry-runs the configuration of datastore clusters, including indices, settings, and scripts"
            task :dry_run do
              print_in_color "#{"=" * 80}\nNOTE: In dry-run mode. The updates reported below will actually be no-ops.\n#{"=" * 80}", GREEN_COLOR_CODE
              update_clusters_for(admin.with_dry_run_datastore_clients)
              print_in_color "#{"=" * 80}\nNOTE: This was dry-run mode. The updates reported above were actually no-ops.\n#{"=" * 80}", GREEN_COLOR_CODE
            end
          end
        end

        namespace :indices do
          desc "Drops all prototype index definitions on all datastore clusters"
          task :drop_prototypes do
            require "elastic_graph/support/threading"

            prototype_indices = admin
              .datastore_core
              .index_definitions_by_name.values
              .select { |index| prototype_index_names.include?(index.name) }
              .reject { |index| index.all_accessible_cluster_names.empty? }

            output.puts "Disabling rollover index auto creation for all clusters"
            admin.cluster_settings_manager.start_index_maintenance_mode!(:all_clusters)
            output.puts "Disabled rollover index auto creation for all clusters"

            output.puts "Dropping the following prototype index definitions: #{prototype_indices.map(&:name).join(",")}"
            Support::Threading.parallel_map(prototype_indices) do |prototype_index_def|
              delete_index_def_in_all_accessible_clusters(prototype_index_def)
            end

            output.puts "Finished dropping all prototype index definitions"
          end

          desc "Drops the specified index definition on the specified datastore cluster"
          task :drop, :index_def_name, :cluster_name do |_, args|
            index_def_name = args.fetch(:index_def_name)
            cluster_name = args.fetch(:cluster_name)
            datastore_client = admin.datastore_core.clients_by_name.fetch(cluster_name) do |key|
              raise Errors::IndexOperationError, "Cluster named `#{key}` does not exist. Valid clusters: #{admin.datastore_core.clients_by_name.keys}."
            end

            index_def = admin.datastore_core.index_definitions_by_name.fetch(index_def_name)
            unless prototype_index_names.include?(index_def.name)
              raise Errors::IndexOperationError, "Unable to drop live index #{index_def_name}. Deleting a live index is extremely dangerous. " \
                "Please ensure this is indeed intended, add the index name to the `prototype_index_names` list and retry."
            end

            output.puts "Disabling rollover index auto creation for this cluster"
            admin.cluster_settings_manager.in_index_maintenance_mode(cluster_name) do
              output.puts "Disabled rollover index auto creation for this cluster"
              output.puts "Dropping index #{index_def}"
              index_def.delete_from_datastore(datastore_client)
              output.puts "Dropped index #{index_def}"
            end
            output.puts "Re-enabled rollover index auto creation for this cluster"
          end
        end
      end

      # See https://en.wikipedia.org/wiki/ANSI_escape_code#Colors for full list.
      RED_COLOR_CODE = 31
      GREEN_COLOR_CODE = 32

      def update_clusters_for(admin)
        configurator = admin.cluster_configurator

        configurator.accessible_index_definitions.tap do |index_defs|
          output.puts "The following index definitions will be configured:\n#{index_defs.map(&:name).join("\n")}"
          configurator.configure_cluster(@output)
        end
      end

      def print_in_color(message, color_code)
        @output.puts "\033[#{color_code}m#{message}\033[0m"
      end

      def delete_index_def_in_all_accessible_clusters(index_def)
        index_def.all_accessible_cluster_names.each do |cluster_name|
          index_def.delete_from_datastore(admin.datastore_core.clients_by_name.fetch(cluster_name))
        end
      end

      def admin
        @admin ||= @load_admin.call
      end
    end
  end
end
