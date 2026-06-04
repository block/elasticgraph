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
      # Computes JSON schema array/nullable layers from schema-definition type references.
      #
      # @private
      module JSONSchemaLayers
        # Returns all JSON schema array/nullable layers of a type, from outermost to innermost.
        # For example, `[[Int]]` returns `[:nullable, :array, :nullable, :array, :nullable]`.
        def self.for(type_reference)
          layers, inner_type = peel_once(type_reference)

          if layers.empty? || inner_type == type_reference
            layers
          else
            layers + self.for(inner_type)
          end
        end

        def self.peel_once(type_reference)
          if type_reference.list?
            inner_type = type_reference.unwrap_list
            return [[:array], inner_type] if type_reference.non_null?
            return [[:nullable, :array], inner_type]
          end

          no_layers = [] # : ::Array[ElasticGraph::SchemaDefinition::jsonSchemaLayer]
          return [no_layers, type_reference.unwrap_non_null] if type_reference.non_null?
          [[:nullable], type_reference]
        end
        private_class_method :peel_once
      end
    end
  end
end
