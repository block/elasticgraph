# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/indexing/field_type/scalar"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        module FieldType
          # JSON-ingestion indexing field type wrapper for scalars.
          #
          # @private
          class Scalar
            def self.wrap(field_type)
              new(field_type)
            end

            def initialize(field_type)
              @field_type = field_type
            end

            def scalar_type
              @field_type.scalar_type
            end

            def to_mapping
              @field_type.to_mapping
            end
          end
        end
      end
    end
  end
end
