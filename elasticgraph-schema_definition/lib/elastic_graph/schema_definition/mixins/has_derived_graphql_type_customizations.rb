# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Mixin that supports the customization of derived GraphQL types.
      #
      # For each type you define, ElasticGraph generates a number of derived GraphQL types that are needed to facilitate the ElasticGraph
      # Query API. Methods in this module can be used to customize those derived GraphQL types.
      module HasDerivedGraphQLTypeCustomizations
        # Registers a customization block for the named derived graphql types. The provided block will get run on the named derived GraphQL
        # types, allowing them to be customized.
        #
        # @param type_names [Array<String, :all>] names of the derived types to customize, or `:all` to customize all derived types
        # @return [void]
        #
        # @example Customize named derived GraphQL types
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID!"
        #       t.index "campaigns"
        #
        #       t.customize_derived_types "CampaignFilterInput", "CampaignSortOrderInput" do |dt|
        #         # Add a `@deprecated` directive to two specific derived types.
        #         dt.directive "deprecated"
        #       end
        #     end
        #   end
        #
        # @example Customize all derived GraphQL types
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID!"
        #       t.index "campaigns"
        #
        #       t.customize_derived_types :all do |dt|
        #         # Add a `@deprecated` directive to all derived types.
        #         dt.directive "deprecated"
        #       end
        #     end
        #   end
        def customize_derived_types(*type_names, &customization_block)
          if type_names.include?(:all)
            derived_type_customizations_for_all_types << customization_block
          else
            type_names.each do |t|
              derived_type_customizations = derived_type_customizations_by_name[t.to_s] # : ::Array[^(::ElasticGraph::SchemaDefinition::_Type) -> void]
              derived_type_customizations << customization_block
            end
          end
        end

        # Registers a customization block for the named fields on the named derived GraphQL type. The provided block will get run on the
        # named fields of the named derived GraphQL type, allowing them to be customized.
        #
        # @param type_name [String] name of the derived type containing fields you want to customize
        # @param field_names [Array<String>] names of the fields on the derived types that you wish to customize
        # @return [void]
        #
        # @example Customize named fields of a derived GraphQL type
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID!"
        #       t.index "campaigns"
        #
        #       t.customize_derived_type_fields "CampaignConnection", "pageInfo", "totalEdgeCount" do |dt|
        #         # Add a `@deprecated` directive to `CampaignConnection.pageInfo` and `CampaignConnection.totalEdgeCount`.
        #         dt.directive "deprecated"
        #       end
        #     end
        #   end
        def customize_derived_type_fields(type_name, *field_names, &customization_block)
          customizations_by_field = derived_field_customizations_by_type_and_field_name[type_name] # : ::Hash[::String, ::Array[^(::ElasticGraph::SchemaDefinition::SchemaElements::Field) -> void]]

          field_names.each do |field_name|
            customizations = customizations_by_field[field_name] # : ::Array[^(::ElasticGraph::SchemaDefinition::SchemaElements::Field) -> void]
            customizations << customization_block
          end
        end

        # @private
        def derived_type_customizations_for_type(type)
          derived_type_customizations = derived_type_customizations_by_name[type.name] # : ::Array[^(::ElasticGraph::SchemaDefinition::_Type) -> void]
          derived_type_customizations + derived_type_customizations_for_all_types
        end

        # @private
        def derived_field_customizations_by_name_for_type(type)
          derived_field_customizations_by_type_and_field_name[type.name] # : ::Hash[::String, ::Array[^(SchemaElements::Field) -> void]]
        end

        # @private
        def derived_type_customizations_by_name
          @derived_type_customizations_by_name ||= ::Hash.new do |hash, type_name|
            hash[type_name] = []
          end
        end

        # @private
        def derived_field_customizations_by_type_and_field_name
          @derived_field_customizations_by_type_and_field_name ||= ::Hash.new do |outer_hash, type|
            outer_hash[type] = ::Hash.new do |inner_hash, field_name|
              inner_hash[field_name] = []
            end
          end
        end

        private

        def derived_type_customizations_for_all_types
          @derived_type_customizations_for_all_types ||= []
        end
      end
    end
  end
end
