# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/filtering/filter_value_set_extractor"

module ElasticGraph
  class GraphQL
    module Filtering
      # Responsible for extracting a constrained set of concrete type names from query filters,
      # based on a `__typename` filter.
      class TypenameFilter
        def initialize(filter_node_interpreter:, schema_names:, known_type_names:)
          @extractor = FilterValueSetExtractor.for_equality(filter_node_interpreter, schema_names)
          @known_type_names = known_type_names
        end

        # Returns the subset of `known_type_names` that satisfy any `__typename` filter in
        # `filter_hashes`. Returns `nil` if the filters place no constraint on `__typename`,
        # meaning all type names are potentially matched.
        def filtered_type_names(filter_hashes)
          typename_set = @extractor.extract_filter_value_set(filter_hashes, ["__typename"])
          return nil unless typename_set

          if typename_set.inclusive?
            typename_set.values.to_a
          else
            @known_type_names - typename_set.values.to_a
          end
        end
      end
    end
  end
end
