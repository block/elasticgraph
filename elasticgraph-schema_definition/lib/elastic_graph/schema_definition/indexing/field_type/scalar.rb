# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    module Indexing
      module FieldType
        # @!parse class Scalar < ::Data; end
        Scalar = ::Data.define(:scalar_type)

        # Responsible for the JSON schema and mapping of a {SchemaElements::ScalarType}.
        #
        # @!attribute [r] scalar_type
        #   @return [SchemaElements::ScalarType] the scalar type
        #
        # @api private
        class Scalar < ::Data
          # @return [Hash<String, ::Object>] the datastore mapping for this scalar type.
          def to_mapping
            Support::HashUtil.stringify_keys(scalar_type.mapping_options)
          end

          # @dynamic initialize, scalar_type
        end
      end
    end
  end
end
