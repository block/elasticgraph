# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Indexing
      # @private
      class RelationshipResolver
        def initialize(schema_def_state:, object_type:, relationship_name:, sourced_fields:)
          @schema_def_state = schema_def_state
          @object_type = object_type
          @relationship_name = relationship_name
          @sourced_fields = sourced_fields
        end

        def resolve
          relation_field = object_type.graphql_fields_by_name[relationship_name]

          if relation_field.nil?
            [nil, "#{relationship_error_prefix} is not defined. Is it misspelled?"]
          elsif (relationship = relation_field.relationship).nil?
            [nil, "#{relationship_error_prefix} is not a relationship. It must be defined using `relates_to_one` or `relates_to_many`."]
          elsif (related_type = schema_def_state.object_types_by_name[relationship.related_type.unwrap_non_null.name]).nil?
            issue =
              if schema_def_state.types_by_name.key?(relationship.related_type.fully_unwrapped.name)
                "references a type which is not an object type: `#{relationship.related_type.name}`. Only object types can be used in relations."
              else
                "references an unknown type: `#{relationship.related_type.name}`. Is it misspelled?"
              end

            [nil, "#{relationship_error_prefix} #{issue}"]
          elsif !related_type.indexed?
            [nil, "#{relationship_error_prefix} references a type which is not indexed: `#{related_type.name}`. Only indexed types can be used in relations."]
          else
            relation_metadata = relation_field.runtime_metadata_graphql_field.relation # : SchemaArtifacts::RuntimeMetadata::Relation
            foreign_key_parent_type = (relation_metadata.direction == :in) ? related_type : object_type

            if (foreign_key_error = validate_foreign_key(foreign_key_parent_type, relation_metadata))
              [nil, foreign_key_error]
            else
              [ResolvedRelationship.new(relationship_name, relation_field, relationship, related_type, relation_metadata), nil]
            end
          end
        end

        private

        # @dynamic schema_def_state, object_type, relationship_name, sourced_fields
        attr_reader :schema_def_state, :object_type, :relationship_name, :sourced_fields

        # Helper method for building the prefix of relationship-related error messages.
        def relationship_error_prefix
          sourced_fields_description =
            if sourced_fields.empty?
              ""
            else
              " (referenced from `sourced_from` on field(s): #{sourced_fields.map { |f| "`#{f.name}`" }.join(", ")})"
            end

          "`#{relationship_description}`#{sourced_fields_description}"
        end

        def validate_foreign_key(foreign_key_parent_type, relation_metadata)
          foreign_key_field = schema_def_state.field_path_resolver.resolve_public_path(foreign_key_parent_type, relation_metadata.foreign_key) { true }
          # If its an inbound foreign key, verify that the foreign key exists on the related type.
          # Note: we don't verify this for outbound foreign keys, because when we define a relationship with an outbound foreign
          # key, we automatically define an indexing only field for the foreign key (since it exists on the same type). We don't
          # do that for an inbound foreign key, though (since the foreign key exists on another type). Allowing a relationship
          # definition on type A to add a field to type B's schema would be weird and surprising.
          if relation_metadata.direction == :in && foreign_key_field.nil?
            "#{relationship_error_prefix} uses `#{foreign_key_parent_type.name}.#{relation_metadata.foreign_key}` as the foreign key, " \
              "but that field does not exist as an indexing field. To continue, define it, define a relationship on `#{foreign_key_parent_type.name}` " \
              "that uses it as the foreign key, use another field as the foreign key, or remove the `#{relationship_description}` definition."
          elsif foreign_key_field && foreign_key_field.type.fully_unwrapped.name != "ID"
            "#{relationship_error_prefix} uses `#{foreign_key_field.fully_qualified_path}` as the foreign key, " \
              "but that field is not an `ID` field as expected. To continue, change it's type, use another field " \
              "as the foreign key, or remove the `#{relationship_description}` definition."
          end
        end

        def relationship_description
          "#{object_type.name}.#{relationship_name}"
        end
      end

      # @private
      ResolvedRelationship = ::Data.define(:relationship_name, :relationship_field, :relationship, :related_type, :relation_metadata)
    end
  end
end
