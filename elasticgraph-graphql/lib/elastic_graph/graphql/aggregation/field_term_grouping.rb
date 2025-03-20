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
      class FieldTermGrouping < Support::MemoizableData.define(:field_path)
        # @dynamic field_path
        include TermGrouping

        private

        def terms_subclause
          {"field" => encoded_index_field_path}
        end
      end
    end
  end
end
