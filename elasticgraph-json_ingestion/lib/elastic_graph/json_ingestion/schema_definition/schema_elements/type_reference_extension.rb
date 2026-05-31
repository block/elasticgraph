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
      module SchemaElements
        # Extends schema-definition type references with JSON schema layer calculation.
        #
        # @private
        module TypeReferenceExtension
          # Returns all JSON schema array/nullable layers of a type, from outermost to innermost.
          # For example, `[[Int]]` returns `[:nullable, :array, :nullable, :array, :nullable]`.
          def json_schema_layers
            @json_schema_layers ||= begin
              layers, inner_type = peel_json_schema_layers_once

              if layers.empty? || inner_type == self
                layers
              else
                layers + inner_type.json_schema_layers
              end
            end
          end

          private

          def peel_json_schema_layers_once
            if list?
              inner_type = unwrap_list # : ElasticGraph::SchemaDefinition::SchemaElements::TypeReference & TypeReferenceExtension
              return [[:array], inner_type] if non_null?
              return [[:nullable, :array], inner_type]
            end

            no_layers = [] # : ::Array[ElasticGraph::SchemaDefinition::jsonSchemaLayer]
            inner_type = unwrap_non_null # : ElasticGraph::SchemaDefinition::SchemaElements::TypeReference & TypeReferenceExtension
            return [no_layers, inner_type] if non_null?
            [[:nullable], self]
          end
        end
      end
    end
  end
end
