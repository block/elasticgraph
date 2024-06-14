# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Defines a generic schema element names API. Defined as a separate class to facilitate easy testing.
      class SchemaElementNamesDefinition
        def self.new(*element_names)
          ::Data.define(:form, :overrides, :exposed_name_by_canonical_name, :canonical_name_by_exposed_name) do
            const_set(:ELEMENT_NAMES, element_names)

            define_method :initialize do |form:, overrides: {}|
              extend(CONVERTERS.fetch(form.to_s) do
                raise Errors::SchemaError,
                  "Invalid schema element name form: #{form.inspect}. " \
                  "Only valid values are: #{CONVERTERS.keys.inspect}."
              end)

              unused_keys = overrides.keys.map(&:to_s) - element_names.map(&:to_s)
              if unused_keys.any?
                raise Errors::SchemaError,
                  "`overrides` contains entries that do not match any schema " \
                  "elements: #{unused_keys.to_a.inspect}. Are any misspelled?"
              end

              exposed_name_by_canonical_name = element_names.each_with_object({}) do |element, names|
                names[element] = overrides.fetch(element) do
                  overrides.fetch(element.to_s) do
                    normalize_case(element.to_s)
                  end
                end.to_s
              end.freeze

              canonical_name_by_exposed_name = exposed_name_by_canonical_name.invert
              validate_no_name_collisions(canonical_name_by_exposed_name, exposed_name_by_canonical_name)

              super(
                form: form,
                overrides: overrides,
                exposed_name_by_canonical_name: exposed_name_by_canonical_name,
                canonical_name_by_exposed_name: canonical_name_by_exposed_name
              )
            end

            # standard:disable Lint/NestedMethodDefinition
            element_names.each do |element|
              method_name = SnakeCaseConverter.normalize_case(element.to_s)
              define_method(method_name) { exposed_name_by_canonical_name.fetch(element) }
            end

            # Returns the _canonical_ name for the given _exposed name_. The canonical name
            # is the name we use within the source code of our framework; the exposed name
            # is the name exposed in the specific GraphQL schema based on the configuration
            # of the project.
            def canonical_name_for(exposed_name)
              canonical_name_by_exposed_name[exposed_name.to_s]
            end

            def self.from_hash(hash)
              new(
                form: hash.fetch(FORM).to_sym,
                overrides: hash[OVERRIDES] || {}
              )
            end

            def to_dumpable_hash
              {
                # Keys here are ordered alphabetically; please keep them that way.
                FORM => form.to_s,
                OVERRIDES => overrides
              }
            end

            def to_s
              "#<#{self.class.name} form=#{form}, overrides=#{overrides}>"
            end
            alias_method :inspect, :to_s

            private

            def validate_no_name_collisions(canonical_name_by_exposed_name, exposed_name_by_canonical_name)
              return if canonical_name_by_exposed_name.size == exposed_name_by_canonical_name.size

              collisions = exposed_name_by_canonical_name
                .group_by { |k, v| v }
                .reject { |v, kv_pairs| kv_pairs.size == 1 }
                .transform_values { |kv_pairs| kv_pairs.map(&:first) }
                .map do |duplicate_exposed_name, canonical_names|
                  "#{canonical_names.inspect} all map to the same exposed name: #{duplicate_exposed_name}"
                end.join(" and ")

              raise Errors::SchemaError, collisions
            end
            # standard:enable Lint/NestedMethodDefinition
          end
        end

        FORM = "form"
        OVERRIDES = "overrides"

        module SnakeCaseConverter
          extend self

          def normalize_case(name)
            name.gsub(/([[:upper:]])/) { "_#{$1.downcase}" }
          end
        end

        module CamelCaseConverter
          extend self

          def normalize_case(name)
            name.gsub(/_(\w)/) { $1.upcase }
          end
        end

        CONVERTERS = {
          "snake_case" => SnakeCaseConverter,
          "camelCase" => CamelCaseConverter
        }
      end

      SchemaElementNames = SchemaElementNamesDefinition.new(
        # Filter arg and operation names:
        :filter,
        :equal_to_any_of, :gt, :gte, :lt, :lte, :matches, :matches_phrase, :matches_query, :any_of, :all_of, :not,
        :time_of_day, :any_satisfy,
        # Directives
        :eg_latency_slo, :ms,
        # For sorting.
        :order_by,
        # For aggregation
        :grouped_by, :count, :count_detail, :aggregated_values, :sub_aggregations,
        # Date/time grouping aggregation fields
        :as_date_time, :as_date, :as_time_of_day, :as_day_of_week,
        # Date/time grouping aggregation arguments
        :offset, :amount, :unit, :time_zone, :truncation_unit,
        # For aggregation counts.
        :approximate_value, :exact_value, :upper_bound,
        # For pagination.
        :first, :after, :last, :before,
        :edges, :node, :nodes, :cursor,
        :page_info, :start_cursor, :end_cursor, :total_edge_count, :has_previous_page, :has_next_page,
        # Subfields of `GeoLocation`/`GeoLocationFilterInput`:
        :latitude, :longitude, :near, :max_distance,
        # Subfields of `MatchesQueryFilterInput`/`MatchesPhraseFilterInput`
        :query, :phrase, :allowed_edits_per_term, :require_all_terms,
        # Aggregated values field names:
        :exact_min, :exact_max, :approximate_min, :approximate_max, :approximate_avg, :approximate_sum, :exact_sum,
        :approximate_distinct_value_count
      )
    end
  end
end
