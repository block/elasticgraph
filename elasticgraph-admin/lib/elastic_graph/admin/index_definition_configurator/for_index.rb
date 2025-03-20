# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/cluster_configurator/action_reporter"
require "elastic_graph/datastore_core/index_config_normalizer"
require "elastic_graph/indexer/hash_differ"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      # Responsible for managing an index's configuration, including both mappings and settings.
      class ForIndex
        # @dynamic index

        attr_reader :index

        def initialize(datastore_client, index, env_agnostic_index_config, output)
          @datastore_client = datastore_client
          @index = index
          @env_agnostic_index_config = env_agnostic_index_config
          @reporter = ClusterConfigurator::ActionReporter.new(output)
        end

        # Attempts to idempotently update the index configuration to the desired configuration
        # exposed by the `IndexDefinition` object. Based on the configuration of the passed index
        # and the state of the index in the datastore, does one of the following:
        #
        #   - If the index did not already exist: creates the index with the desired mappings and settings.
        #   - If the desired mapping has fewer fields than what is in the index: raises an exception,
        #     because the datastore provides no way to remove fields from a mapping and it would be confusing
        #     for this method to silently ignore the issue.
        #   - If the settings have desired changes: updates the settings, restoring any setting that
        #     no longer has a desired value to its default.
        #   - If the mapping has desired changes: updates the mappings.
        #
        # Note that any of the writes to the index may fail. There are many things that cannot
        # be changed on an existing index (such as static settings, field mapping types, etc). We do not attempt
        # to validate those things ahead of time and instead rely on the datastore to fail if an invalid operation
        # is attempted.
        def configure!
          return create_new_index unless index_exists?

          # Update settings before mappings, to front-load the API call that is more likely to fail.
          # Our `validate` method guards against mapping changes that are known to be disallowed by
          # the datastore, but it is much harder to validate that for settings, because there are so
          # many settings, and there is not clear documentation that outlines all settings, which can
          # be updated on existing indices, etc.
          #
          # If we get a failure, we'd rather it happen before any changes are applied to the index, instead
          # of applying the mappings and then failing on the settings.
          update_settings if settings_updates.any?

          update_mapping if has_mapping_updates?
        end

        def validate
          if index_exists? && mapping_type_changes.any?
            [cannot_modify_mapping_field_type_error]
          else
            []
          end
        end

        private

        def create_new_index
          @datastore_client.create_index(index: @index.name, body: desired_config)
          report_action "Created index: `#{@index.name}`"
        end

        def update_mapping
          @datastore_client.put_index_mapping(index: @index.name, body: desired_mapping)
          action_description = "Updated mappings for index `#{@index.name}`:\n#{mapping_diff}"

          if mapping_removals.any?
            action_description += "\n\nNote: the extra fields listed here will not actually get removed. " \
              "Mapping removals are unsupported (but ElasticGraph will leave them alone and they'll cause no problems)."
          end

          report_action action_description
        end

        def update_settings
          @datastore_client.put_index_settings(index: @index.name, body: settings_updates)
          report_action "Updated settings for index `#{@index.name}`:\n#{settings_diff}"
        end

        def cannot_modify_mapping_field_type_error
          "The datastore does not support modifying the type of a field from an existing index definition. " \
          "You are attempting to update type of fields (#{mapping_type_changes.inspect}) from the #{@index.name} index definition."
        end

        def index_exists?
          !current_config.empty?
        end

        def mapping_removals
          @mapping_removals ||= mapping_fields_from(current_mapping) - mapping_fields_from(desired_mapping)
        end

        def mapping_type_changes
          @mapping_type_changes ||= begin
            flattened_current = Support::HashUtil.flatten_and_stringify_keys(current_mapping)
            flattened_desired = Support::HashUtil.flatten_and_stringify_keys(desired_mapping)

            flattened_current.keys.select do |key|
              key.end_with?(".type") && flattened_desired.key?(key) && flattened_desired[key] != flattened_current[key]
            end
          end
        end

        def has_mapping_updates?
          current_mapping != desired_mapping
        end

        def settings_updates
          @settings_updates ||= begin
            # Updating a setting to null will cause the datastore to restore the default value of the setting.
            restore_to_defaults = (current_settings.keys - desired_settings.keys).to_h { |key| [key, nil] }
            desired_settings.select { |key, value| current_settings[key] != value }.merge(restore_to_defaults)
          end
        end

        def mapping_fields_from(mapping_hash, prefix = "")
          (mapping_hash["properties"] || []).flat_map do |key, params|
            field = prefix + key
            if params.key?("properties")
              [field] + mapping_fields_from(params, "#{field}.")
            else
              [field]
            end
          end
        end

        def desired_mapping
          desired_config.fetch("mappings")
        end

        def desired_settings
          @desired_settings ||= desired_config.fetch("settings")
        end

        def desired_config
          @desired_config ||= begin
            # _meta is place where we can record state on the index mapping in the datastore.
            # We want to maintain `_meta.ElasticGraph.sources` as an append-only set of all sources that have ever
            # been configured to flow into an index, so that we can remember whether or not an index which currently
            # has no `sourced_from` from fields ever did. This is necessary for our automatic filtering of multi-source
            # indexes.
            previously_recorded_sources = current_mapping.dig("_meta", "ElasticGraph", "sources") || []
            sources = previously_recorded_sources.union(@index.current_sources.to_a).sort

            DatastoreCore::IndexConfigNormalizer.normalize(Support::HashUtil.deep_merge(@env_agnostic_index_config, {
              "mappings" => {"_meta" => {"ElasticGraph" => {"sources" => sources}}},
              "settings" => @index.flattened_env_setting_overrides
            }))
          end
        end

        def current_mapping
          current_config["mappings"] || {}
        end

        def current_settings
          @current_settings ||= current_config["settings"]
        end

        def current_config
          @current_config ||= DatastoreCore::IndexConfigNormalizer.normalize(
            @datastore_client.get_index(@index.name)
          )
        end

        def mapping_diff
          @mapping_diff ||= Indexer::HashDiffer.diff(current_mapping, desired_mapping) || "(no diff)"
        end

        def settings_diff
          @settings_diff ||= Indexer::HashDiffer.diff(current_settings, desired_settings) || "(no diff)"
        end

        def report_action(message)
          @reporter.report_action(message)
        end
      end
    end
  end
end
