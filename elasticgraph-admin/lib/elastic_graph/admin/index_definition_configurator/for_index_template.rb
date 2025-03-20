# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/cluster_configurator/action_reporter"
require "elastic_graph/admin/index_definition_configurator/for_index"
require "elastic_graph/datastore_core/index_config_normalizer"
require "elastic_graph/indexer/hash_differ"
require "elastic_graph/support/hash_util"

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      # Responsible for managing an index template's configuration, including both mappings and settings.
      class ForIndexTemplate
        # @dynamic index_template

        attr_reader :index_template

        def initialize(datastore_client, index_template, env_agnostic_index_config_parent, output, clock)
          @datastore_client = datastore_client
          @index_template = index_template
          @env_agnostic_index_config_parent = env_agnostic_index_config_parent
          @env_agnostic_index_config = env_agnostic_index_config_parent.fetch("template")
          @reporter = ClusterConfigurator::ActionReporter.new(output)
          @output = output
          @clock = clock
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
          related_index_configurators.each(&:configure!)

          # there is no partial update for index template config and the same API both creates and updates it
          put_index_template if has_mapping_updates? || settings_updates.any?
        end

        def validate
          errors = related_index_configurators.flat_map(&:validate)

          return errors unless index_template_exists?

          errors << cannot_modify_mapping_field_type_error if mapping_type_changes.any?

          errors
        end

        private

        def put_index_template
          desired_template_config_payload = Support::HashUtil.deep_merge(
            desired_config_parent,
            {"template" => {"mappings" => merge_properties(desired_mapping, current_mapping)}}
          )

          action_description = "Updated index template: `#{@index_template.name}`:\n#{config_diff}"

          if mapping_removals.any?
            action_description += "\n\nNote: the extra fields listed here will not actually get removed. " \
              "Mapping removals are unsupported (but ElasticGraph will leave them alone and they'll cause no problems)."
          end

          @datastore_client.put_index_template(name: @index_template.name, body: desired_template_config_payload)
          report_action action_description
        end

        def cannot_modify_mapping_field_type_error
          "The datastore does not support modifying the type of a field from an existing index definition. " \
          "You are attempting to update type of fields (#{mapping_type_changes.inspect}) from the #{@index_template.name} index definition."
        end

        def index_template_exists?
          !current_config_parent.empty?
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
          desired_config_parent.fetch("template").fetch("mappings")
        end

        def desired_settings
          @desired_settings ||= desired_config_parent.fetch("template").fetch("settings")
        end

        def desired_config_parent
          @desired_config_parent ||= begin
            # _meta is place where we can record state on the index mapping in the datastore.
            # We want to maintain `_meta.ElasticGraph.sources` as an append-only set of all sources that have ever
            # been configured to flow into an index, so that we can remember whether or not an index which currently
            # has no `sourced_from` from fields ever did. This is necessary for our automatic filtering of multi-source
            # indexes.
            previously_recorded_sources = current_mapping.dig("_meta", "ElasticGraph", "sources") || []
            sources = previously_recorded_sources.union(@index_template.current_sources.to_a).sort

            env_agnostic_index_config_with_meta =
              DatastoreCore::IndexConfigNormalizer.normalize(Support::HashUtil.deep_merge(@env_agnostic_index_config, {
                "mappings" => {"_meta" => {"ElasticGraph" => {"sources" => sources}}},
                "settings" => @index_template.flattened_env_setting_overrides
              }))

            @env_agnostic_index_config_parent.merge({"template" => env_agnostic_index_config_with_meta})
          end
        end

        def current_mapping
          current_config_parent.dig("template", "mappings") || {}
        end

        def current_settings
          @current_settings ||= current_config_parent.dig("template", "settings")
        end

        def current_config_parent
          @current_config_parent ||= begin
            config = @datastore_client.get_index_template(@index_template.name)
            if (template = config.dig("template"))
              config.merge({"template" => DatastoreCore::IndexConfigNormalizer.normalize(template)})
            else
              config
            end
          end
        end

        def config_diff
          @config_diff ||= Indexer::HashDiffer.diff(current_config_parent, desired_config_parent) || "(no diff)"
        end

        def report_action(message)
          @reporter.report_action(message)
        end

        # Helper method used to merge properties between a _desired_ configuration and a _current_ configuration.
        # This is used when we are figuring out how to update an index template. We do not want to delete existing
        # fields from a template--while the datastore would allow it, our schema evolution strategy depends upon
        # us not dropping old unused fields. The datastore doesn't allow it on indices, anyway (though it does allow
        # it on index templates). We've ran into trouble (a near SEV) when allowing the logic here to delete an unused
        # field from an index template. The indexer "mapping completeness" check started failing because an old version
        # of the code (from back when the field in question was still used) noticed the expected field was missing and
        # started failing on every event.
        #
        # This helps us avoid that problem by retaining any currently existing fields.
        #
        # Long term, if we want to support fully "garbage collecting" these old fields on templates, we will need
        # to have them get dropped in a follow up step. We could have our `update_datastore_config` script notice that
        # the deployed prod indexers are at a version that will tolerate the fields being dropped, or support it
        # via an opt-in flag or something.
        def merge_properties(desired_object, current_object)
          desired_properties = desired_object.fetch("properties") { _ = {} }
          current_properties = current_object.fetch("properties") { _ = {} }

          merged_properties = desired_properties.merge(current_properties) do |key, desired, current|
            if current.is_a?(::Hash) && current.key?("properties") && desired.key?("properties")
              merge_properties(desired, current)
            else
              desired
            end
          end

          desired_object.merge("properties" => merged_properties)
        end

        def related_index_configurators
          # Here we fan out and get a configurator for each related index. These are generally concrete
          # index that are based on a template, either via being specified in our config YAML, or via
          # auto creation at indexing time.
          #
          # Note that it should not matter whether the related indices are configured before of after
          # its rollover template; our use of index maintenance mode below prevents new indidces from
          # being auto-created while this configuration process runs.
          @related_index_configurators ||= begin
            rollover_indices = @index_template.related_rollover_indices(@datastore_client)

            # When we have a rollover index, it's important that we make at least one concrete index. Otherwise, if any
            # queries come in before the first event is indexed, we won't have any concrete indices to search, and
            # the datastore returns a response that differs from normal in that case. It particularly creates trouble
            # for aggregation queries since the response format it expects is quite complex.
            #
            # Here we create a concrete index for the current timestamp if there are no concrete indices yet.
            if rollover_indices.empty?
              rollover_indices = [@index_template.related_rollover_index_for_timestamp(@clock.now.getutc.iso8601)].compact
            end

            rollover_indices.map do |index|
              IndexDefinitionConfigurator::ForIndex.new(@datastore_client, index, @env_agnostic_index_config, @output)
            end
          end
        end
      end
    end
  end
end
