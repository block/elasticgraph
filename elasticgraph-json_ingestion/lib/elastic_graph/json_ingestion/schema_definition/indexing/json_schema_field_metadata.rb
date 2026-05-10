# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        # @!parse class JSONSchemaFieldMetadata; end
        JSONSchemaFieldMetadata = ::Data.define(:type, :name_in_index)

        # Metadata about an ElasticGraph field that needs to be stored in our versioned JSON schemas.
        #
        # @api private
        class JSONSchemaFieldMetadata < ::Data
          # @return [Hash<String, String>] hash representation suitable for serialization
          def to_dumpable_hash
            {"type" => type, "nameInIndex" => name_in_index}
          end

          # @dynamic initialize, type, name_in_index
        end
      end
    end
  end
end
