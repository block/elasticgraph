# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/time_set"
require "elastic_graph/errors"
require "time"

module ElasticGraph
  class DatastoreCore
    module Configuration
      # Defines environment-specific customizations for an index definition.
      #
      # - ignore_routing_values: routing values for which we will ignore routing as configured on the index.
      #   This is intended to be used when a single routing value contains such a large portion of the dataset that it creates lopsided shards.
      #   By including that routing value in this config setting, it'll spread that value's data across all shards instead of concentrating it on a single shard.
      # - query_cluster: named search cluster to be used for queries on this index.
      # - index_into_cluster: named search clusters to index data into.
      # - setting_overrides: overrides for index (or index template) settings.
      # - setting_overrides_by_timestamp: overrides for index template settings for specific dates,
      #   allowing us to have different settings than the template for some timestamp.
      # - custom_timestamp_ranges: defines indices for a custom timestamp range (rather than relying
      #   on the configured rollover frequency).
      # - use_updates_for_indexing: when `true`, opts the index into using the `update` API instead of the `index` API for indexing.
      #   (Defaults to `true`).
      class IndexDefinition < ::Data.define(
        :ignore_routing_values,
        :query_cluster,
        :index_into_clusters,
        :setting_overrides,
        :setting_overrides_by_timestamp,
        :custom_timestamp_ranges,
        :use_updates_for_indexing
      )
        def initialize(ignore_routing_values:, **rest)
          __skip__ = super(ignore_routing_values: ignore_routing_values.to_set, **rest)

          # Verify the custom ranges are disjoint.
          # Yeah, this is O(N^2), which isn't great, but we expect a _very_ small number of custom
          # ranges (0-2) so this should be ok.
          return if custom_timestamp_ranges
            .map(&:time_set)
            .combination(2)
            .none? do |s1_s2|
              s1, s2 = s1_s2
              s1.intersect?(s2)
            end

          raise Errors::ConfigError, "Your configured `custom_timestamp_ranges` are not disjoint, as required."
        end

        def without_env_overrides
          with(setting_overrides: {}, setting_overrides_by_timestamp: {}, custom_timestamp_ranges: [])
        end

        def custom_timestamp_range_for(timestamp)
          custom_timestamp_ranges.find do |range|
            range.time_set.member?(timestamp)
          end
        end

        def self.definitions_by_name_hash_from(index_def_hash_by_name)
          index_def_hash_by_name.transform_values do |index_def_hash|
            __skip__ = from(**index_def_hash.transform_keys(&:to_sym))
          end
        end

        def self.from(custom_timestamp_ranges:, use_updates_for_indexing: true, **rest)
          __skip__ = new(
            custom_timestamp_ranges: CustomTimestampRange.ranges_from(custom_timestamp_ranges),
            use_updates_for_indexing: use_updates_for_indexing,
            **rest
          )
        end

        # Represents an index definition that is based on a custom timestamp range.
        class CustomTimestampRange < ::Data.define(:index_name_suffix, :setting_overrides, :time_set)
          def initialize(index_name_suffix:, setting_overrides:, time_set:)
            super

            if time_set.empty?
              raise Errors::ConfigError, "Custom timestamp range with suffix `#{index_name_suffix}` is invalid: no timestamps exist in it."
            end
          end

          def self.ranges_from(range_hashes)
            range_hashes.map do |range_hash|
              __skip__ = from(**range_hash.transform_keys(&:to_sym))
            end
          end

          private_class_method def self.from(index_name_suffix:, setting_overrides:, **predicates_hash)
            if predicates_hash.empty?
              raise Errors::ConfigSettingNotSetError, "Custom timestamp range with suffix `#{index_name_suffix}` lacks boundary definitions."
            end

            range_options = predicates_hash.transform_values { |iso8601_string| ::Time.iso8601(iso8601_string) }
            time_set = Support::TimeSet.of_range(**range_options)

            new(index_name_suffix: index_name_suffix, setting_overrides: setting_overrides, time_set: time_set)
          end
        end
      end
    end
  end
end
