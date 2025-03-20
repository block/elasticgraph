# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/argument_extension"
require "elastic_graph/apollo/schema_definition/enum_type_extension"
require "elastic_graph/apollo/schema_definition/enum_value_extension"
require "elastic_graph/apollo/schema_definition/field_extension"
require "elastic_graph/apollo/schema_definition/input_type_extension"
require "elastic_graph/apollo/schema_definition/interface_type_extension"
require "elastic_graph/apollo/schema_definition/object_type_extension"
require "elastic_graph/apollo/schema_definition/scalar_type_extension"
require "elastic_graph/apollo/schema_definition/union_type_extension"

module ElasticGraph
  module Apollo
    module SchemaDefinition
      # Extension module applied to `ElasticGraph::SchemaDefinition::Factory` to add Apollo tagging support.
      #
      # @private
      module FactoryExtension
        # Steep has a hard type with the arg splats here.
        __skip__ = def new_field(**kwargs)
                     super(**kwargs) do |field|
                       field.extend FieldExtension
                       yield field if block_given?
                     end
                   end

        def new_argument(field, name, value_type)
          super(field, name, value_type) do |type|
            type.extend ArgumentExtension
            yield type if block_given?
          end
        end

        def new_enum_type(name)
          super(name) do |type|
            type.extend EnumTypeExtension
            yield type
          end
        end

        def new_enum_value(name, original_name)
          super(name, original_name) do |type|
            type.extend EnumValueExtension
            yield type if block_given?
          end
        end

        def new_input_type(name)
          super(name) do |type|
            type.extend InputTypeExtension
            yield type
          end
        end

        def new_interface_type(name)
          super(name) do |type|
            type.extend InterfaceTypeExtension
            yield type
          end
        end

        # Here we override `object_type` in order to automatically add the apollo `@key` directive to indexed types.
        def new_object_type(name)
          super(name) do |raw_type|
            raw_type.extend ObjectTypeExtension
            type = raw_type # : ElasticGraph::SchemaDefinition::SchemaElements::ObjectType & ObjectTypeExtension

            yield type if block_given?

            if type.indexed? && type.graphql_fields_by_name.key?("id")
              type.apollo_key fields: "id"
            end
          end
        end

        def new_scalar_type(name)
          super(name) do |type|
            type.extend ScalarTypeExtension
            yield type
          end
        end

        def new_union_type(name)
          super(name) do |type|
            type.extend UnionTypeExtension
            yield type
          end
        end
      end
    end
  end
end
