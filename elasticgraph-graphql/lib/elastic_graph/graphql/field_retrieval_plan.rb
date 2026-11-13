# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class GraphQL
    # Carries search parameters and decodes retrieved fields into the document payload.
    # @private
    class FieldRetrievalPlan < ::Data.define(:source, :docvalue_fields, :reason)
      # @dynamic with
      SOURCE = new(source: true, docvalue_fields: [], reason: "source_default")

      def to_datastore_body
        body = {_source: source} # : ::Hash[::Symbol, untyped]
        body[:docvalue_fields] = docvalue_fields unless docvalue_fields.empty?
        body
      end

      def decode(hit)
        docvalue_fields.to_h do |field|
          fields = hit["fields"] || {} # : ::Hash[::String, ::Array[untyped]]
          values = fields.fetch(field, [])
          if values.size > 1
            raise Errors::SearchFailedError, "Expected a scalar for doc-value field `#{field}`. Verify existing data before enabling automatic retrieval."
          end
          [field, values.first]
        end
      end
    end
  end
end
