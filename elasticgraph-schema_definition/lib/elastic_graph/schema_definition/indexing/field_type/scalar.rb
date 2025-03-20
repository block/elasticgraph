# Copyright 2024 - 2025 Block, Inc.
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

          # @return [Hash<String, ::Object>] the JSON schema for this scalar type.
          def to_json_schema
            Support::HashUtil.stringify_keys(scalar_type.json_schema_options)
          end

          # @return [Hash<String, ::Object>] additional ElasticGraph metadata to put in the JSON schema for this scalar type.
          def json_schema_field_metadata_by_field_name
            {}
          end

          # @param customizations [Hash<String, ::Object>] JSON schema customizations
          # @return [Hash<String, ::Object>] formatted customizations.
          def format_field_json_schema_customizations(customizations)
            customizations
          end

          # @dynamic initialize, scalar_type
        end
      end
    end
  end
end
