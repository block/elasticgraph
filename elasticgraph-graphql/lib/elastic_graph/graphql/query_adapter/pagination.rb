# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    class QueryAdapter
      # Note: This class is not tested directly but indirectly through specs on `QueryAdapter`
      Pagination = Data.define(:schema_element_names) do
        # @implements Pagination
        def call(query:, args:, lookahead:, field:, context:)
          return query unless field.type.unwrap_fully.indexed_document?

          document_pagination = [:first, :before, :last, :after].to_h do |key|
            [key, args[schema_element_names.public_send(key)]]
          end

          query.merge_with(document_pagination: document_pagination)
        end
      end
    end
  end
end
