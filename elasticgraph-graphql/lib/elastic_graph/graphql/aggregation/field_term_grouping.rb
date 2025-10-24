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
      class FieldTermGrouping < Support::MemoizableData.define(:field_path, :field)
        # @dynamic field_path, field
        include TermGrouping

        # Random 18 bytes converted to base64. Used 18 bytes instead of 16 to avoid base64 padding.
        # Since it uses more bytes, this has a lower probability of collission than a 16 byte random UUID.
        MISSING_STRING_PLACEHOLDER = "f1TXKoApWwIG3U8ks9vVduvU"
        MISSING_NUMERIC_PLACEHOLDER = "NaN"

        def missing_value_placeholder
          unwrapped_type = field.type.unwrap_fully
          case unwrapped_type.name
          when "String", "ID"
            MISSING_STRING_PLACEHOLDER
          when "Int", "JsonSafeLong", "Float"
            MISSING_NUMERIC_PLACEHOLDER
          else
            unwrapped_type.enum? ? MISSING_STRING_PLACEHOLDER : nil
          end
        end

        private
          
        def terms_subclause
          {"field" => encoded_index_field_path}
        end
      end
    end
  end
end
