# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/schema_elements/type_with_subfields"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Represents a GraphQL `input` (used primarily for filtering).
      #
      # @private
      class InputType < DelegateClass(TypeWithSubfields)
        include Mixins::HasReadableToSAndInspect.new { |t| t.name }

        def initialize(schema_def_state, name)
          schema_def_state.factory.new_type_with_subfields(
            :input, name,
            wrapping_type: self,
            field_factory: schema_def_state.factory.method(:new_input_field)
          ) do |type|
            # Here we clear `reserved_field_names` because those field names are reserved precisely for our usage
            # here on input filters. If we don't set this to an empty set we'll get exceptions in `new_filter` above
            # when we generate our standard filter operators.
            #
            # Note: we opt-out of the reserved field names here rather then opting in on the other `TypeWithSubfields`
            # subtypes because this is the only case where we don't want the reserved field name check applied (but we
            # have multiple subtypes where we do want it applied).
            type.reserved_field_names = Set.new

            super(type)
            graphql_only true
            yield self
          end
        end

        def runtime_metadata(extra_update_targets)
          graphql_input_fields_by_name = graphql_fields_by_name.transform_values do |field|
            field.runtime_metadata_graphql_field.with(resolver: nil)
          end

          SchemaArtifacts::RuntimeMetadata::ObjectType.new(
            update_targets: extra_update_targets,
            index_definition_names: [],
            graphql_fields_by_name: graphql_input_fields_by_name,
            elasticgraph_category: nil,
            source_type: nil,
            graphql_only_return_type: false
          )
        end

        def derived_graphql_types
          []
        end
      end
    end
  end
end
