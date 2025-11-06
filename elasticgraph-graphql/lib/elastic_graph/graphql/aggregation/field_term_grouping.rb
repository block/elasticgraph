# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/term_grouping"

module ElasticGraph
  class GraphQL
    module Aggregation
      class FieldTermGrouping < Support::MemoizableData.define(:field_path, :missing_value_placeholder)
        # @dynamic field_path
        include TermGrouping

        # Returns true if this grouping handles missing values using a placeholder value
        # instead of a separate missing aggregation.
        #
        # @return [Boolean] true if missing values are handled via placeholder
        def handles_missing_values?
          !missing_value_placeholder.nil?
        end

        def non_composite_clause_for(query)
          return super unless handles_missing_values?

          Support::HashUtil.deep_merge(super, {"terms" => {"missing" => missing_value_placeholder}})
        end

        def inner_meta
          return super unless handles_missing_values?

          super.merge({"missing_values" => [missing_value_placeholder]})
        end

        private

        def terms_subclause
          {"field" => encoded_index_field_path}
        end
      end
    end
  end
end
