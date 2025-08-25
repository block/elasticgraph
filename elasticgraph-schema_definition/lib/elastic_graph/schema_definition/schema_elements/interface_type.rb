# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/schema_definition/mixins/has_indices"
require "elastic_graph/schema_definition/mixins/has_subtypes"
require "elastic_graph/schema_definition/mixins/implements_interfaces"
require "elastic_graph/schema_definition/mixins/supports_filtering_and_aggregation"
require "elastic_graph/schema_definition/schema_elements/type_with_subfields"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # {include:API#interface_type}
      #
      # @example Define an interface
      #   ElasticGraph.define_schema do |schema|
      #     schema.interface_type "Athlete" do |t|
      #       # in the block, `t` is an InterfaceType
      #     end
      #   end
      class InterfaceType < DelegateClass(TypeWithSubfields)
        # As of the October 2021 GraphQL spec, interfaces can now implement other interfaces:
        # http://spec.graphql.org/October2021/#sec-Interfaces.Interfaces-Implementing-Interfaces
        # Originated from: graphql/graphql-spec#373
        include Mixins::ImplementsInterfaces
        include Mixins::SupportsFilteringAndAggregation
        include Mixins::HasIndices
        include Mixins::HasSubtypes
        include Mixins::HasReadableToSAndInspect.new { |t| t.name }

        # @dynamic to_indexing_field_type

        # @private
        def initialize(schema_def_state, name)
          field_factory = schema_def_state.factory.method(:new_field)
          schema_def_state.factory.new_type_with_subfields(:interface, name, wrapping_type: self, field_factory: field_factory) do |type|
            __skip__ = super(type) do
              yield self
            end
          end
        end

        # This contains more than just the proper interface fields; it also contains the fields from the
        # subtypes, which winds up being used to generate an input filter and aggregation type.
        #
        # For just the interface fields, use `interface_fields_by_name`.
        #
        # @private
        def graphql_fields_by_name
          merged_fields_from_subtypes_by_name = super # delegates to the `HasSubtypes` definition.
          # The interface field definitions should take precedence over the merged fields from the subtypes.
          merged_fields_from_subtypes_by_name.merge(interface_fields_by_name)
        end

        # @private
        def interface_fields_by_name
          __getobj__.graphql_fields_by_name
        end

        private

        def resolve_subtypes
          schema_def_state.implementations_by_interface_ref[type_ref]
        end
      end
    end
  end
end
