# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/errors"
require "elastic_graph/schema_definition/schema_elements/field"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Wraps a {Field} to provide additional relationship-specific functionality when defining a field via
      # {TypeWithSubfields#relates_to_one} or {TypeWithSubfields#relates_to_many}.
      #
      # @example Define relationships between two types
      #   ElasticGraph.define_schema do |schema|
      #     schema.object_type "Orchestra" do |t|
      #       t.field "id", "ID"
      #       t.relates_to_many "musicians", "Musician", via: "orchestraId", dir: :in, singular: "musician" do |r|
      #         # In this block, `r` is a `Relationship`.
      #       end
      #       t.index "orchestras"
      #     end
      #
      #     schema.object_type "Musician" do |t|
      #       t.field "id", "ID"
      #       t.field "instrument", "String"
      #       t.relates_to_one "orchestra", "Orchestra", via: "orchestraId", dir: :out do |r|
      #         # In this block, `r` is a `Relationship`.
      #       end
      #       t.index "musicians"
      #     end
      #   end
      class Relationship < DelegateClass(Field)
        # @dynamic related_type, hide_relationship_runtime_metadata, hide_relationship_runtime_metadata=

        # @return [ObjectType, InterfaceType, UnionType] the type this relationship relates to
        attr_reader :related_type

        # @private
        attr_accessor :hide_relationship_runtime_metadata

        # @private
        def initialize(field, cardinality:, related_type:, foreign_key:, direction:)
          super(field)
          self.hide_relationship_runtime_metadata = false
          @cardinality = cardinality
          @related_type = related_type
          @foreign_key = foreign_key
          @direction = direction
          @equivalent_field_paths_by_local_path = {}
          @additional_filter = {}
        end

        # Adds additional filter conditions to a relationship beyond the foreign key.
        #
        # @param filter [Hash<Symbol, Object>, Hash<String, Object>] additional filter conditions for this relationship
        # @return [void]
        #
        # @example Define additional filter conditions on a `relates_to_one` relationship
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Orchestra" do |t|
        #       t.field "id", "ID"
        #       t.relates_to_many "musicians", "Musician", via: "orchestraId", dir: :in, singular: "musician"
        #       t.relates_to_one "firstViolin", "Musician", via: "orchestraId", dir: :in do |r|
        #         r.additional_filter isFirstViolon: true
        #       end
        #
        #       t.index "orchestras"
        #     end
        #
        #     schema.object_type "Musician" do |t|
        #       t.field "id", "ID"
        #       t.field "instrument", "String"
        #       t.field "isFirstViolon", "Boolean"
        #       t.relates_to_one "orchestra", "Orchestra", via: "orchestraId", dir: :out
        #       t.index "musicians"
        #     end
        #   end
        def additional_filter(filter)
          stringified_filter = Support::HashUtil.stringify_keys(filter)
          @additional_filter = Support::HashUtil.deep_merge(@additional_filter, stringified_filter)
        end

        # Indicates that `path` (a field on the related type) is the equivalent of `locally_named` on this type.
        #
        # Use this API to specify a local field's equivalent path on the related type. This must be used on relationships used by
        # {Field#sourced_from} when the local type uses {Indexing::Index#route_with} or {Indexing::Index#rollover} so that
        # ElasticGraph can determine what field from the related type to use to route the update requests to the correct index and shard.
        #
        # @param path [String] path to a routing or rollover field on the related type
        # @param locally_named [String] path on the local type to the equivalent field
        # @return [void]
        #
        # @example
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID!"
        #       t.field "name", "String"
        #       t.field "createdAt", "DateTime"
        #
        #       t.relates_to_one "launchPlan", "CampaignLaunchPlan", via: "campaignId", dir: :in do |r|
        #         r.equivalent_field "campaignCreatedAt", locally_named: "createdAt"
        #       end
        #
        #       t.field "launchDate", "Date" do |f|
        #         f.sourced_from "launchPlan", "launchDate"
        #       end
        #
        #       t.index "campaigns"do |i|
        #         i.rollover :yearly, "createdAt"
        #       end
        #     end
        #
        #     schema.object_type "CampaignLaunchPlan" do |t|
        #       t.field "id", "ID"
        #       t.field "campaignId", "ID"
        #       t.field "campaignCreatedAt", "DateTime"
        #       t.field "launchDate", "Date"
        #
        #       t.index "campaign_launch_plans"
        #     end
        #   end
        def equivalent_field(path, locally_named: path)
          if @equivalent_field_paths_by_local_path.key?(locally_named)
            raise Errors::SchemaError, "`equivalent_field` has been called multiple times on `#{parent_type.name}.#{name}` with the same " \
              "`locally_named` value (#{locally_named.inspect}), but each local field can have only one `equivalent_field`."
          else
            @equivalent_field_paths_by_local_path[locally_named] = path
          end
        end

        # Gets the `routing_value_source` from this relationship for the given `index`, based on the configured
        # routing used by `index` and the configured equivalent fields.
        #
        # Returns the GraphQL field name (not the `name_in_index`).
        #
        # @private
        def routing_value_source_for_index(index)
          return nil unless index.uses_custom_routing?

          index_routing_field_path = index.routing_field_path # : FieldPath
          @equivalent_field_paths_by_local_path.fetch(index_routing_field_path.path) do |local_need|
            yield local_need
          end
        end

        # Gets the `rollover_timestamp_value_source` from this relationship for the given `index`, based on the
        # configured equivalent fields and the rollover configuration used by `index`.
        #
        # Returns the GraphQL field name (not the `name_in_index`).
        #
        # @private
        def rollover_timestamp_value_source_for_index(index)
          return nil unless (rollover_config = index.rollover_config)

          @equivalent_field_paths_by_local_path.fetch(rollover_config.timestamp_field_path.path) do |local_need|
            yield local_need
          end
        end

        # @private
        def validate_equivalent_fields(field_path_resolver)
          resolved_related_type = (_ = related_type.as_object_type) # : indexableType

          @equivalent_field_paths_by_local_path.flat_map do |local_path_string, related_type_path_string|
            errors = [] # : ::Array[::String]

            local_path = resolve_and_validate_field_path(parent_type, local_path_string, field_path_resolver) do |error|
              errors << error
            end

            related_type_path = resolve_and_validate_field_path(resolved_related_type, related_type_path_string, field_path_resolver) do |error|
              errors << error
            end

            if local_path && related_type_path && local_path.type.unwrap_non_null != related_type_path.type.unwrap_non_null
              errors << "Field `#{related_type_path.full_description}` is defined as an equivalent of " \
                "`#{local_path.full_description}` via an `equivalent_field` definition on `#{parent_type.name}.#{name}`, " \
                "but their types do not agree. To continue, change one or the other so that they agree."
            end

            errors
          end
        end

        # @private
        def many?
          @cardinality == :many
        end

        # @private
        def runtime_metadata
          return nil if hide_relationship_runtime_metadata

          resolved_related_type = (_ = related_type.unwrap_list.as_object_type) # : indexableType
          foreign_key_nested_paths = schema_def_state.field_path_resolver.determine_nested_paths(resolved_related_type, @foreign_key)
          foreign_key_nested_paths ||= [] # : ::Array[::String]
          SchemaArtifacts::RuntimeMetadata::Relation.new(
            foreign_key: @foreign_key,
            direction: @direction,
            additional_filter: @additional_filter,
            foreign_key_nested_paths: foreign_key_nested_paths
          )
        end

        private

        def resolve_and_validate_field_path(type, field_path_string, field_path_resolver)
          field_path = field_path_resolver.resolve_public_path(type, field_path_string) do |parent_field|
            !parent_field.type.list?
          end

          if field_path.nil?
            yield "Field `#{type.name}.#{field_path_string}` (referenced from an `equivalent_field` defined on " \
              "`#{parent_type.name}.#{name}`) does not exist. Either define it or correct the `equivalent_field` definition."
          end

          field_path
        end
      end
    end
  end
end
