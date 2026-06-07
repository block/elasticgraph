# Copyright 2024 - 2026 Block, Inc.
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
          relationship = object_type.relationships_by_name[relationship_name]

          if relationship.nil?
            if object_type.graphql_fields_by_name.key?(relationship_name)
              [nil, "#{relationship_error_prefix} is not a relationship. It must be defined using `relates_to_one` or `relates_to_many`."]
            else
              [nil, "#{relationship_error_prefix} is not defined. Is it misspelled?"]
            end
          elsif (related_type = schema_def_state.object_types_by_name[relationship.related_type.unwrap_non_null.name]).nil?
            issue =
              if schema_def_state.types_by_name.key?(relationship.related_type.fully_unwrapped.name)
                "references a type which is not an object type: `#{relationship.related_type.name}`. Only object types can be used in relations."
              else
                "references an unknown type: `#{relationship.related_type.name}`. Is it misspelled?"
              end

            [nil, "#{relationship_error_prefix} #{issue}"]
          elsif !related_type.root_document_type?
            [nil, "#{relationship_error_prefix} references a type which is not a root document type: `#{related_type.name}`. Only root document types can be used in relations."]
          else
            relation_metadata = relationship.runtime_metadata # : SchemaArtifacts::RuntimeMetadata::Relation
            foreign_key_parent_type = (relation_metadata.direction == :in) ? related_type : object_type
            referenced_parent_type = (relation_metadata.direction == :in) ? object_type : related_type

            if (foreign_key_error = validate_foreign_key(foreign_key_parent_type, relation_metadata))
              [nil, foreign_key_error]
            elsif (referenced_field_error = validate_referenced_field(referenced_parent_type, relation_metadata))
              [nil, referenced_field_error]
            else
              [ResolvedRelationship.new(relationship_name, relationship, related_type, relation_metadata), nil]
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

        def validate_referenced_field(referenced_parent_type, relation_metadata)
          referenced_field = schema_def_state.field_path_resolver.resolve_public_path(referenced_parent_type, relation_metadata.referenced_field_name) { true }
          # If it's an outbound relationship, verify that the referenced field exists on the related type.
          # Note: we don't verify this for inbound relationships, because when we define a relationship with an inbound
          # foreign key, we automatically define an indexing only field for the referenced field (since it exists on the
          # same type). We don't do that for outbound relationships, though (since the referenced field exists on another
          # type). Allowing a relationship definition on type A to add a field to type B's schema would be weird and surprising.
          if relation_metadata.direction == :out && referenced_field.nil?
            "#{relationship_error_prefix} uses `#{referenced_parent_type.name}.#{relation_metadata.referenced_field_name}` as the `references` field, " \
              "but that field does not exist as an indexing field. To continue, define it on `#{referenced_parent_type.name}`, " \
              "use another field as the `references` target, or remove the `#{relationship_description}` definition."
          # For indexed types (root document types), the referenced field must be "id" (the document ID field).
          # This is because the indexer uses foreign key values directly as document IDs for updates
          # (see Mixins::HasIndices where normal indexing update targets are created with `id_source: "id"`).
          # Embedded types don't have this constraint since they don't have document IDs - the `references`
          # parameter is only meaningful for matching nested objects within embedded types.
          elsif referenced_parent_type.root_document_type? && relation_metadata.referenced_field_name != "id"
            "#{relationship_error_prefix} uses `references: \"#{relation_metadata.referenced_field_name}\"` " \
              "on indexed type `#{referenced_parent_type.name}`, but the `references` parameter can only be customized " \
              "for relationships to embedded types. For indexed types, `references` must be \"id\" because ElasticGraph " \
              "uses foreign key values directly as document `_id` values when updating related documents, and document IDs " \
              "are always sourced from the \"id\" field. To fix this, remove the `references` parameter (it defaults to \"id\")."
          end
        end

        def relationship_description
          "#{object_type.name}.#{relationship_name}"
        end
      end

      # @private
      ResolvedRelationship = ::Data.define(:relationship_name, :relationship, :related_type, :relation_metadata)
    end
  end
end
