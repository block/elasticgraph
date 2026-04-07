# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        module FieldType
          # Wraps a scalar indexing field type to add JSON schema serialization.
          class Scalar < ::SimpleDelegator
            # @return [Hash] empty hash, as scalar types have no subfields
            def json_schema_field_metadata_by_field_name
              {}
            end

            # Returns the customizations as-is for scalar types.
            #
            # @param customizations [Hash<String, Object>] the customizations to format
            # @return [Hash<String, Object>] the formatted customizations
            def format_field_json_schema_customizations(customizations)
              customizations
            end

            # @return [Hash<String, Object>] the JSON schema definition for this scalar type
            def to_json_schema
              Support::HashUtil.stringify_keys(__getobj__.scalar_type.json_schema_options)
            end
          end
        end
      end
    end
  end
end
