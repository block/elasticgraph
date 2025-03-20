# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "date"
require "elastic_graph/datastore_core/index_config_normalizer"
require "elastic_graph/datastore_core/index_definition/base"
require "elastic_graph/datastore_core/index_definition/index"
require "elastic_graph/datastore_core/index_definition/rollover_index"
require "elastic_graph/errors"
require "elastic_graph/support/memoizable_data"
require "elastic_graph/support/time_set"
require "elastic_graph/support/time_util"
require "time"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      class RolloverIndexTemplate < Support::MemoizableData.define(
        :name, :route_with, :default_sort_clauses, :current_sources, :fields_by_path, :env_index_config,
        :index_args, :defined_clusters, :datastore_clients_by_name, :timestamp_field_path, :frequency
      )
        # `Data.define` provides all these methods:
        # @dynamic name, route_with, default_sort_clauses, current_sources, fields_by_path, env_index_config,
        # @dynamic index_args, defined_clusters, datastore_clients_by_name, timestamp_field_path, frequency, initialize

        # `include IndexDefinition::Base` provides all these methods. Steep should be able to detect it
        # but can't for some reason so we have to declare them with `@dynamic`.
        # @dynamic flattened_env_setting_overrides, routing_value_for_prepared_record, has_custom_routing?, cluster_to_query, use_updates_for_indexing?
        # @dynamic clusters_to_index_into, all_accessible_cluster_names, ignored_values_for_routing, searches_could_hit_incomplete_docs?
        # @dynamic accessible_cluster_names_to_index_into, accessible_from_queries?, known_related_query_rollover_indices, list_counts_field_paths_for_source
        include IndexDefinition::Base

        def mappings_in_datastore(datastore_client)
          IndexConfigNormalizer.normalize_mappings(
            datastore_client.get_index_template(name).dig("template", "mappings") || {}
          )
        end

        # We need to delete both the template and the actual indices for rollover indices
        def delete_from_datastore(datastore_client)
          datastore_client.delete_index_template(name)
          datastore_client.delete_indices(index_expression_for_search)
        end

        # Indicates if this is a rollover index definition.
        #
        # Use of this is considered a mild code smell.  When feasible, it's generally better to
        # implement a new polymorphic API on the IndexDefinition interface, rather
        # then branching on the value of this predicate.
        def rollover_index_template?
          true
        end

        # Two underscores used to avoid collisions
        # with other types (e.g. payments_2020 and payments_xyz_2020), though regardless shouldn't
        # happen if types follow naming conventions.
        def index_expression_for_search
          index_name_with_suffix("*")
        end

        # Returns an index name to use for write operations. The index_definition selection is a function of
        # the index_definition's rollover configuration and the record's timestamp.
        def index_name_for_writes(record, timestamp_field_path: nil)
          index_name_with_suffix(rollover_index_suffix_for_record(
            record,
            timestamp_field_path: timestamp_field_path || self.timestamp_field_path
          ))
        end

        # Returns a list of indices related to this template. This includes both indices that are
        # specified in our configuration settings (e.g. via `setting_overrides_by_timestamp` and
        # `custom_time_sets`) and also indices that have been auto-created from the template.
        #
        # Note that there can be discrepancies between the configuration settings and the indices in
        # the datastore. Sometimes this is planned/expected (e.g. such as when invoking `elasticgraph-admin`
        # to configure an index newly defined in configuration) and in other cases it's not.
        #
        # The `only_if_exists` argument controls how a discrepancy is treated.
        #
        # - When `false` (the default), indices that are defined in config but do not exist in the datastore are still returned.
        #   This is generally what we want for indexing and cluster administration.
        # - When `true`, any indices in our configuration that do not exist are ignored, and not included in the returned list.
        #   This is appropriate for searching the datastore: if we attempt to exclude an index which is defined in config but does
        #   not exist (e.g. via `-[index_name]` in the search index expression), the datastore will return an error, but we can
        #   safely ignore the index. Likewise, if we have an index in the datastore which we cannot infer a timestamp range, we
        #   need to ignore it to avoid getting errors. Ignoring an index is safe when searching because our search logic uses a
        #   wildcard to match _all_ indices with the same prefix, and then excludes certain known indices that it can safely
        #   exclude based on their timestamp range. Ignored indices which exist will still be searched.
        #
        # In addition, any indices which exist, but which are not controlled by our current configuration, are ignored. Examples:
        #
        #  - An index with a custom suffix (e.g. `__before_2019`) which has no corresponding configuration. We have no way to guess
        #    what the timestamp range is for such an index, and we want to completely ignore it.
        #  - An index with for a different rollover frequency than our current configuration. For example, a `__2019-03` index,
        #    which must rollover monthly, would be ignored if our current rollover frequency is yearly or daily.
        #
        # These latter cases are quite rare but can happen when we are dealing with indices defined before an update to our
        # configuration. Our searches will continue to search these indices so long as their name matches the pattern, and
        # we otherwise want to ignore these indices (e.g. we don't want admin to attempt to configure them, or want our
        # indexer to attempt to write to them).
        def related_rollover_indices(datastore_client, only_if_exists: false)
          config_indices_by_name = rollover_indices_to_pre_create.to_h { |i| [i.name, i] }

          db_indices_by_name = datastore_client.list_indices_matching(index_expression_for_search).filter_map do |name|
            index = concrete_rollover_index_for(name, {}, config_indices_by_name[name]&.time_set)
            [name, index] if index
          end.to_h

          config_indices_by_name = config_indices_by_name.slice(*db_indices_by_name.keys) if only_if_exists

          db_indices_by_name.merge(config_indices_by_name).values
        end

        # Gets a single related `RolloverIndex` for a given timestamp.
        def related_rollover_index_for_timestamp(timestamp, setting_overrides = {})
          # @type var record: ::Hash[::String, untyped]
          # We need to use `__skip__` here because `inner_value` has different types on different
          # block iterations: initially, it's a string, then it becomes a hash. Steep has trouble
          # with this but it works fine.
          __skip__ = record = timestamp_field_path.split(".").reverse.reduce(timestamp) do |inner_value, field_name|
            {field_name => inner_value}
          end

          concrete_rollover_index_for(index_name_for_writes(record), setting_overrides)
        end

        private

        def after_initialize
          unless timestamp_field_path && ROLLOVER_SUFFIX_FORMATS_BY_FREQUENCY.key?(frequency)
            raise Errors::SchemaError, "Rollover index config 'timestamp_field' or 'frequency' is invalid."
          end
        end

        # Returns a list of indices that must be pre-created (rather than allowing them to be
        # created lazily based on the template). This is done so that we can use different
        # index settings for some indices. For example, you might want your template to be
        # configured to use 5 shards, but for old months with a small data set you may only
        # want to use 1 shard.
        def rollover_indices_to_pre_create
          @rollover_indices_to_pre_create ||= begin
            indices_with_overrides = setting_overrides_by_timestamp.filter_map do |(timestamp, setting_overrides)|
              related_rollover_index_for_timestamp(timestamp, setting_overrides)
            end

            indices_for_custom_timestamp_ranges = custom_timestamp_ranges.filter_map do |range|
              concrete_rollover_index_for(
                index_name_with_suffix(range.index_name_suffix),
                range.setting_overrides,
                range.time_set
              )
            end

            indices_with_overrides + indices_for_custom_timestamp_ranges
          end
        end

        def setting_overrides_by_timestamp
          env_index_config.setting_overrides_by_timestamp
        end

        def custom_timestamp_ranges
          env_index_config.custom_timestamp_ranges
        end

        def index_name_with_suffix(suffix)
          "#{name}#{ROLLOVER_INDEX_INFIX_MARKER}#{suffix}"
        end

        ROLLOVER_SUFFIX_FORMATS_BY_FREQUENCY = {hourly: "%Y-%m-%d-%H", daily: "%Y-%m-%d", monthly: "%Y-%m", yearly: "%Y"}
        ROLLOVER_TIME_ELEMENT_COUNTS_BY_FREQUENCY = ROLLOVER_SUFFIX_FORMATS_BY_FREQUENCY.transform_values { |format| format.split("-").size }
        TIME_UNIT_BY_FREQUENCY = {hourly: :hour, daily: :day, monthly: :month, yearly: :year}

        def rollover_index_suffix_for_record(record, timestamp_field_path:)
          timestamp_value = ::DateTime.iso8601(
            Support::HashUtil.fetch_value_at_path(record, timestamp_field_path)
          ).to_time

          if (matching_custom_range = env_index_config.custom_timestamp_range_for(timestamp_value))
            return matching_custom_range.index_name_suffix
          end

          timestamp_value.strftime(ROLLOVER_SUFFIX_FORMATS_BY_FREQUENCY.fetch(frequency))
        end

        def concrete_rollover_index_for(index_name, setting_overrides, time_set = nil)
          time_set ||= infer_time_set_from_index_name(index_name)
          return nil if time_set.nil?

          args = index_args.merge({
            name: index_name,
            env_index_config: env_index_config.without_env_overrides.with(
              setting_overrides: env_index_config.setting_overrides.merge(setting_overrides)
            )
          })

          RolloverIndex.new(Index.new(**args), time_set)
        end

        def infer_time_set_from_index_name(index_name)
          time_args = index_name.split(ROLLOVER_INDEX_INFIX_MARKER).last.to_s.split("-")

          # Verify that the index is for the same rollover frequency as we are currently configured to use.
          # If not, return `nil` because we can't accurately infer the time set without the frequency aligning
          # with the index itself.
          #
          # This can happen when we are migrating from one index frequency to another.
          return nil unless time_args.size == ROLLOVER_TIME_ELEMENT_COUNTS_BY_FREQUENCY.fetch(frequency)

          # Verify that the args are all numeric. If not, return `nil` because we have no idea what the
          # time set for the index is.
          #
          # This can happen when we are migrating from one index configuration to another while also using
          # custom timestamp ranges (e.g. to have a `__before_2020` index).
          return nil if time_args.any? { |arg| /\A\d+\z/ !~ arg }

          # Steep can't type the dynamic nature of `*time_args` so we have to use `__skip__` here.
          # @type var lower_bound: ::Time
          __skip__ = lower_bound = ::Time.utc(*time_args)
          upper_bound = Support::TimeUtil.advance_one_unit(lower_bound, TIME_UNIT_BY_FREQUENCY.fetch(frequency))

          Support::TimeSet.of_range(gte: lower_bound, lt: upper_bound)
        end
      end
    end
  end
end
