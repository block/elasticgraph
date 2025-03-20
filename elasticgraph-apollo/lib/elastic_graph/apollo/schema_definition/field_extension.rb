# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/apollo_directives"

module ElasticGraph
  module Apollo
    module SchemaDefinition
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::Field} to offer Apollo field directives.
      module FieldExtension
        include ApolloDirectives::Authenticated
        include ApolloDirectives::External
        include ApolloDirectives::Inaccessible
        include ApolloDirectives::Override
        include ApolloDirectives::Policy
        include ApolloDirectives::Provides
        include ApolloDirectives::Requires
        include ApolloDirectives::RequiresScopes
        include ApolloDirectives::Shareable
        include ApolloDirectives::Tag

        # Extension method designed to support Apollo's [contract variant tagging](https://www.apollographql.com/docs/studio/contracts/).
        #
        # Calling this method on a field will cause the field and every schema element derived from the field (e.g. the filter field,
        # he aggregation field, etc), to be tagged with the given `tag_name`, ensuring that all capabilities related to the field are
        # available in the contract variant.
        #
        # @param tag_name [String] tag to add to schema elements generated for this field
        # @return [void]
        #
        # @example Tag a field (and its derived elements) with "public"
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "name", "String" do |f|
        #         f.tag_with "public"
        #       end
        #     end
        #   end
        #
        # @see ApolloDirectives::Tag
        # @see APIExtension#tag_built_in_types_with
        def tag_with(tag_name)
          on_each_generated_schema_element do |element|
            needs_tagging =
              if element.is_a?(ElasticGraph::SchemaDefinition::SchemaElements::SortOrderEnumValue)
                # Each sort order enum value is based on a full field path (e.g. `parentField_subField_furtherNestedField_ASC`).
                # We must only tag the enum if each part of the full field path is also tagged. In this example, we should only
                # tag the enum value if `parentField`, `subField`, and `furtherNestedField` are all tagged.
                element.sort_order_field_path.all? { |f| FieldExtension.tagged_with?(f, tag_name) }
              else
                true
              end

            if needs_tagging && !FieldExtension.tagged_with?(element, tag_name)
              (_ = element).apollo_tag name: tag_name
            end
          end
        end

        # Helper method that indicates if the given schema element has a specific tag.
        #
        # @param element [Object] element to check
        # @param tag_name [String] tag to check
        # @return [Boolean]
        def self.tagged_with?(element, tag_name)
          element.directives.any? { |dir| dir.name == "tag" && dir.arguments == {name: tag_name} }
        end
      end
    end
  end
end
