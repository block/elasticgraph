# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Abstraction for generating names for GraphQL enum values. This allows users to customize the
      # naming of our built-in enum values.
      #
      # @private
      class EnumValueNamer < ::Struct.new(:overrides_by_type_name)
        def initialize(overrides_by_type_name = {})
          overrides_by_type_name = Support::HashUtil
            .stringify_keys(overrides_by_type_name) # : ::Hash[::String, ::Hash[::String, ::String]]

          @used_value_names_by_type_name = ::Hash.new { |h, k| h[k] = [] }
          validate_overrides(overrides_by_type_name)
          super(overrides_by_type_name: overrides_by_type_name)
        end

        # Returns the name that should be used for the given `type_name` and `value_name`.
        def name_for(type_name, value_name)
          used_value_names = @used_value_names_by_type_name[type_name] # : ::Array[::String]
          used_value_names << value_name
          overrides_by_type_name.dig(type_name, value_name) || value_name
        end

        # Returns the overrides that did not wind up being used. Unused overrides usually happen
        # because of a typo, and can be safely removed.
        def unused_overrides
          overrides_by_type_name.filter_map do |type_name, overrides|
            if @used_value_names_by_type_name.key?(type_name)
              unused_overrides = overrides.except(*@used_value_names_by_type_name.fetch(type_name))
              [type_name, unused_overrides] unless unused_overrides.empty?
            else
              [type_name, overrides]
            end
          end.to_h
        end

        # Full set of enum type and value names that were used. Can be used to provide suggestions
        # for when there are `unused_overrides`.
        def used_value_names_by_type_name
          @used_value_names_by_type_name.dup
        end

        private

        def validate_overrides(overrides_by_type_name)
          duplicate_problems = overrides_by_type_name.flat_map do |type_name, overrides|
            overrides
              .group_by { |k, v| v }
              .transform_values { |kv_pairs| kv_pairs.map(&:first) }
              .select { |_, v| v.size > 1 }
              .map do |override, source_names|
                "Multiple `#{type_name}` enum value overrides (#{source_names.sort.join(", ")}) map to the same name (#{override}), which is not supported."
              end
          end

          invalid_name_problems = overrides_by_type_name.flat_map do |type_name, overrides|
            overrides.filter_map do |source_name, override|
              unless GRAPHQL_NAME_PATTERN.match(override)
                "`#{override}` (the override for `#{type_name}.#{source_name}`) is not a valid GraphQL type name. " +
                  GRAPHQL_NAME_VALIDITY_DESCRIPTION
              end
            end
          end

          notify_problems(duplicate_problems + invalid_name_problems)
        end

        def notify_problems(problems)
          return if problems.empty?

          raise Errors::ConfigError, "Provided `enum_value_overrides_by_type_name` have #{problems.size} problem(s):\n\n" \
            "#{problems.map.with_index(1) { |problem, i| "#{i}. #{problem}" }.join("\n\n")}"
        end
      end
    end
  end
end
