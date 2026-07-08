# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/cluster_configurator/action_reporter"
require "elastic_graph/admin/index_definition_configurator/for_index"
require "elastic_graph/admin/index_definition_configurator/mapping_update"
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
        #   - If the desired mapping has fewer fields than what is in the index template: preserves fields
        #     that the schema definition still references (via `deleted_field`/`renamed_from` declarations)
        #     and drops fields whose last schema reference has been removed (see `put_index_template`).
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

        # Creates or updates the index template. Fields that exist on the current template but not in the
        # desired configuration are dropped only when it is provably safe. New rollover indices are
        # auto-created from the template at indexing time with `dynamic: strict` mappings, so dropping a
        # field that something can still write would cause indexing failures on those new indices--we have
        # previously had a near-SEV from dropping a template field while deployed indexers were still
        # running an old version of the code that used it. So, as long as a field is referenced by a
        # `deleted_field` or `renamed_from` declaration in the schema definition (meaning an old JSON
        # schema version may still reference it, and an indexer deployed with an older schema version or a
        # replayed old event may still write it), we preserve it via `field_paths_protected_from_removal`.
        # Once the last reference is removed from the schema definition--which `eg-schema_def` only
        # sanctions once no JSON schema version references the field--the field is dropped on the next
        # admin run, keeping templates from accumulating stale fields forever.
        def put_index_template
          action_description = if index_template_exists?
            "Updated index template: `#{@index_template.name}`:\n#{config_diff}#{removed_fields_note}"
          else
            "Created index template: `#{@index_template.name}`"
          end

          @datastore_client.put_index_template(name: @index_template.name, body: desired_config_parent_for_update)
          report_action action_description
        end

        # Dropped fields show up as deletions in the reported diff, but we also call them out explicitly
        # since a field removal is the part of a mapping update most worth a second look from operators.
        def removed_fields_note
          removed_fields = mapping_field_paths_of(current_mapping) - mapping_field_paths_of(desired_mapping_for_update)
          return "" if removed_fields.empty?

          "\n\n" + <<~EOS.chomp
            Removed #{removed_fields.size} stale field(s) from index template `#{@index_template.name}` that are no longer referenced by the schema: #{removed_fields.join(", ")}.
            New rollover indices created from this template will reject documents that still contain these fields (mappings are `dynamic: strict`).
          EOS
        end

        def mapping_field_paths_of(mapping, parent_path: "")
          mapping.fetch("properties", MappingUpdate::EMPTY_PROPERTIES).flat_map do |field_name, field_mapping|
            path = "#{parent_path}#{field_name}"
            [path] + mapping_field_paths_of(field_mapping, parent_path: "#{path}.")
          end
        end

        def cannot_modify_mapping_field_type_error
          "The datastore does not support modifying the type of a field from an existing index definition. " \
          "You are attempting to update type of fields (#{mapping_type_changes.inspect}) from the #{@index_template.name} index definition."
        end

        def index_template_exists?
          !current_config_parent.empty?
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
          current_mapping != desired_mapping_for_update
        end

        def settings_updates
          @settings_updates ||= begin
            # Updating a setting to null will cause the datastore to restore the default value of the setting.
            restore_to_defaults = (current_settings.keys - desired_settings.keys).to_h { |key| [key, nil] }
            desired_settings.select { |key, value| current_settings[key] != value }.merge(restore_to_defaults)
          end
        end

        def desired_mapping_for_update
          @desired_mapping_for_update ||= MappingUpdate.build_mapping_update(
            desired: desired_mapping,
            current: current_mapping,
            protected_field_paths: @index_template.field_paths_protected_from_removal
          )
        end

        def desired_config_parent_for_update
          @desired_config_parent_for_update ||= Support::HashUtil.deep_merge(
            desired_config_parent,
            {"template" => {"mappings" => desired_mapping_for_update}}
          )
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
          @config_diff ||= Indexer::HashDiffer.diff(current_config_parent, desired_config_parent_for_update) || "(no diff)"
        end

        def report_action(message)
          @reporter.report_action(message)
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
