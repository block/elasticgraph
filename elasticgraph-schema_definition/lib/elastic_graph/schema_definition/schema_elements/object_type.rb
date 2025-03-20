# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/errors"
require "elastic_graph/schema_definition/mixins/has_indices"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/mixins/implements_interfaces"
require "elastic_graph/schema_definition/schema_elements/type_with_subfields"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # {include:API#object_type}
      #
      # @example Define an object type
      #   ElasticGraph.define_schema do |schema|
      #     schema.object_type "Money" do |t|
      #       # in the block, `t` is an ObjectType
      #     end
      #   end
      class ObjectType < DelegateClass(TypeWithSubfields)
        # DelegateClass(TypeWithSubfields) provides the following methods:
        # @dynamic name, type_ref, to_sdl, derived_graphql_types, to_indexing_field_type, current_sources, index_field_runtime_metadata_tuples, graphql_only?, relay_pagination_type
        include Mixins::SupportsFilteringAndAggregation

        # `include HasIndices` provides the following methods:
        # @dynamic runtime_metadata, derived_indexed_types, indices, indexed?, abstract?
        include Mixins::HasIndices

        # `include ImplementsInterfaces` provides the following methods:
        # @dynamic verify_graphql_correctness!
        include Mixins::ImplementsInterfaces
        include Mixins::HasReadableToSAndInspect.new { |t| t.name }

        # @private
        def initialize(schema_def_state, name)
          field_factory = schema_def_state.factory.method(:new_field)
          schema_def_state.factory.new_type_with_subfields(:type, name, wrapping_type: self, field_factory: field_factory) do |type|
            __skip__ = super(type) do
              yield self
            end
          end
        end
      end
    end
  end
end
