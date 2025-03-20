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
      # Used for term groupings that use a script instead of a field
      class ScriptTermGrouping < Support::MemoizableData.define(:field_path, :script_id, :params)
        # @dynamic field_path
        include TermGrouping

        private

        def terms_subclause
          {
            "script" => {
              "id" => script_id,
              "params" => params.merge({"field" => encoded_index_field_path})
            }
          }
        end
      end
    end
  end
end
