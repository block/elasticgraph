# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/graphql_field"
require "elastic_graph/schema_artifacts/runtime_metadata/hash_dumper"
require "elastic_graph/schema_artifacts/runtime_metadata/update_target"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      # Provides runtime metadata related to object types.
      class ObjectType < ::Data.define(
        :update_targets,
        :index_definition_names,
        :graphql_fields_by_name,
        :elasticgraph_category,
        # Indicates the name of the GraphQL type from which this type was generated. Note that a `nil` value doesn't
        # imply that this type was user-defined; we have recently introduced this metadata and are not yet setting
        # it for all generated GraphQL types. For now, we are only setting it for specific cases where we need it.
        :source_type,
        :graphql_only_return_type
      )
        UPDATE_TARGETS = "update_targets"
        INDEX_DEFINITION_NAMES = "index_definition_names"
        GRAPHQL_FIELDS_BY_NAME = "graphql_fields_by_name"
        ELASTICGRAPH_CATEGORY = "elasticgraph_category"
        SOURCE_TYPE = "source_type"
        GRAPHQL_ONLY_RETURN_TYPE = "graphql_only_return_type"

        def initialize(update_targets:, index_definition_names:, graphql_fields_by_name:, elasticgraph_category:, source_type:, graphql_only_return_type:)
          graphql_fields_by_name = graphql_fields_by_name.select { |name, field| field.needed?(name) }

          super(
            update_targets: update_targets,
            index_definition_names: index_definition_names,
            graphql_fields_by_name: graphql_fields_by_name,
            elasticgraph_category: elasticgraph_category,
            source_type: source_type,
            graphql_only_return_type: graphql_only_return_type
          )
        end

        def self.from_hash(hash)
          update_targets = hash[UPDATE_TARGETS]&.map do |update_target_hash|
            UpdateTarget.from_hash(update_target_hash)
          end || []

          graphql_fields_by_name = hash[GRAPHQL_FIELDS_BY_NAME]&.to_h do |name, field_hash|
            field_hash = field_hash.merge(GraphQLField::NAME_IN_INDEX => name) unless field_hash[GraphQLField::NAME_IN_INDEX]
            [name, GraphQLField.from_hash(field_hash)]
          end || {}

          new(
            update_targets: update_targets,
            index_definition_names: hash[INDEX_DEFINITION_NAMES] || [],
            graphql_fields_by_name: graphql_fields_by_name,
            elasticgraph_category: hash[ELASTICGRAPH_CATEGORY]&.to_sym || nil,
            source_type: hash[SOURCE_TYPE] || nil,
            graphql_only_return_type: !!hash[GRAPHQL_ONLY_RETURN_TYPE]
          )
        end

        def to_dumpable_hash
          dumped_graphql_fields_by_name =
            HashDumper.dump_hash(graphql_fields_by_name.to_h do |name, field|
              field = field.with(name_in_index: nil) if field.name_in_index == name
              [name, field]
            end, &:to_dumpable_hash)

          {
            # Keys here are ordered alphabetically; please keep them that way.
            ELASTICGRAPH_CATEGORY => elasticgraph_category&.to_s,
            GRAPHQL_FIELDS_BY_NAME => dumped_graphql_fields_by_name,
            GRAPHQL_ONLY_RETURN_TYPE => graphql_only_return_type ? true : nil,
            INDEX_DEFINITION_NAMES => index_definition_names,
            SOURCE_TYPE => source_type,
            UPDATE_TARGETS => update_targets.map(&:to_dumpable_hash)
          }
        end
      end
    end
  end
end
