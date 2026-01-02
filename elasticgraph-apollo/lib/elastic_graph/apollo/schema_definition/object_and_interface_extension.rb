# Copyright 2024 - 2026 Block, Inc.
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
      # Extends {ElasticGraph::SchemaDefinition::SchemaElements::ObjectType} and
      # {ElasticGraph::SchemaDefinition::SchemaElements::InterfaceType} to offer some Apollo-specific APIs.
      module ObjectAndInterfaceExtension
        # Exposes an Apollo entity reference as a new field, backed by an `ID` field.
        #
        # When integrating an ElasticGraph project as a subgraph into a larger Apollo supergraph, it's useful to be able
        # to reference entities owned by other subgraphs. The most straightforward way to do this is to define an
        # _entity reference_ type (e.g. a type containing just the `@key` fields such as `id: ID` and marked as
        # `resolvable: false` in the `@key` directive), and then define fields using that type. This approach works
        # particularly well when you plan ahead and know which `ID` fields to model with entity reference types.
        #
        # However, on an existing schema where you've got some raw `ID` fields of external entities, it can be quite
        # difficult to replace the `ID` fields with full-blown entity reference types, as doing so would require migrating
        # clients and running a full backfill.
        #
        # This API provides an alternate solution for this situation: it defines a GraphQL-only field which returns an entity
        # reference type using a custom GraphQL resolver.
        #
        # See the [Apollo docs on referencing an entity without contributing
        # fields](https://www.apollographql.com/docs/graphos/schema-design/federated-schemas/entities/contribute-fields#referencing-an-entity-without-contributing-fields)
        # for more information.
        #
        # @param name [String] Name of the field
        # @param type [String] Name of the entity reference type (which must be defined separately)
        # @param id_field_name_in_index [String] Name of the backing ID field in the datastore index
        # @return [void]
        # @note This can be used for either a singleton or list reference, based on if `type` is a list.
        # @note The resulting field will be only be available for clients to request as a return field. It will not support filtering,
        #   sorting, grouping, aggregated values, or highlights.
        # @see #apollo_entity_ref_paginated_collection_field
        #
        # @example Expose `Review.product` and `Review.comments` entity reference fields
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Product" do |t|
        #       t.field "id", "ID"
        #       t.apollo_key fields: "id", resolvable: false
        #     end
        #
        #     schema.object_type "Comment" do |t|
        #       t.field "id", "ID"
        #       t.apollo_key fields: "id", resolvable: false
        #     end
        #
        #     schema.object_type "Review" do |t|
        #       t.field "id", "ID"
        #       t.field "score", "Int"
        #
        #       # Fields originally defined in the first version of the schema
        #       t.field "productId", "ID"
        #       t.field "commentIds", "[ID!]!"
        #
        #       # New field we're adding to expose the existing `productId` field as a `Product` entity reference.
        #       t.apollo_entity_ref_field "product", "Product", id_field_name_in_index: "productId"
        #
        #       # New field we're adding to expose the existing `commentIds` field as a list of `Comment` entity references.
        #       t.apollo_entity_ref_field "comments", "[Comment!]!", id_field_name_in_index: "commentIds"
        #
        #       t.index "reviews"
        #     end
        #   end
        def apollo_entity_ref_field(name, type, id_field_name_in_index:)
          field(
            name,
            type,
            name_in_index: id_field_name_in_index,
            **LIMITED_GRAPHQL_ONLY_FIELD_OPTIONS
          ) do |f|
            validate_entity_ref_options(__method__.to_s, f, id_field_name_in_index, type) do |exposed_id_field|
              if f.type.list?
                f.resolve_with :apollo_entity_ref_list, source_ids_field: id_field_name_in_index, exposed_id_field: exposed_id_field
              else
                f.resolve_with :apollo_entity_ref, source_id_field: id_field_name_in_index, exposed_id_field: exposed_id_field
              end
            end

            yield f if block_given?
          end
        end

        # Exposes a collection of Apollo entity references as a new paginated field, backed by an `ID` field.
        #
        # When integrating an ElasticGraph project as a subgraph into a larger Apollo supergraph, it's useful to be able
        # to reference entities owned by other subgraphs. The most straightforward way to do this is to define an
        # _entity reference_ type (e.g. a type containing just the `@key` fields such as `id: ID` and marked as
        # `resolvable: false` in the `@key` directive), and then define fields using that type. This approach works
        # particularly well when you plan ahead and know which `ID` fields to model with entity reference types.
        #
        # However, on an existing schema where you've got some raw `ID` fields of external entities, it can be quite
        # difficult to replace the `ID` fields with full-blown entity reference types, as doing so would require migrating
        # clients and running a full backfill.
        #
        # This API provides an alternate solution for this situation: it defines a GraphQL-only field which returns an entity
        # reference type using a custom GraphQL resolver. In contrast to {#apollo_entity_ref_field}, this defines a field as
        # a [paginated Relay connection](https://relay.dev/graphql/connections.htm) rather than a simple list.
        #
        # See the [Apollo docs on referencing an entity without contributing
        # fields](https://www.apollographql.com/docs/graphos/schema-design/federated-schemas/entities/contribute-fields#referencing-an-entity-without-contributing-fields)
        # for more information.
        #
        # @param name [String] Name of the field
        # @param element_type [String] Name of the entity reference type (which must be defined separately)
        # @param id_field_name_in_index [String] Name of the backing ID field in the datastore index
        # @return [void]
        # @note This requires `id_field_name_in_index` to be a list or paginated collection field.
        # @note The resulting field will be only be available for clients to request as a return field. It will not support filtering,
        #   sorting, grouping, aggregated values, or highlights.
        # @see #apollo_entity_ref_field
        # @see ElasticGraph::SchemaDefinition::SchemaElements::TypeWithSubfields#paginated_collection_field
        #
        # @example Expose `Review.product` and `Review.comments` entity reference fields
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Comment" do |t|
        #       t.field "id", "ID"
        #       t.apollo_key fields: "id", resolvable: false
        #     end
        #
        #     schema.object_type "Review" do |t|
        #       t.field "id", "ID"
        #       t.field "score", "Int"
        #
        #       # Field originally defined in the first version of the schema
        #       t.field "commentIds", "[ID!]!"
        #
        #       # New field we're adding to expose the existing `commentIds` field as a list of `Comment` entity references.
        #       t.apollo_entity_ref_paginated_collection_field "comments", "Comment", id_field_name_in_index: "commentIds"
        #
        #       t.index "reviews"
        #     end
        #   end
        def apollo_entity_ref_paginated_collection_field(name, element_type, id_field_name_in_index:)
          paginated_collection_field(
            name,
            element_type,
            name_in_index: id_field_name_in_index,
            **LIMITED_GRAPHQL_ONLY_PAGINATED_FIELD_OPTIONS
          ) do |f|
            validate_entity_ref_options(__method__.to_s, f, id_field_name_in_index, element_type) do |exposed_id_field|
              backing_indexing_field = f.backing_indexing_field # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field
              unless backing_indexing_field.type.list?
                raise Errors::SchemaError, "`#{f.parent_type.name}.#{f.name}` is invalid: `id_field_name_in_index` must reference an " \
                  "id collection field, but the type of `#{id_field_name_in_index}` is `#{backing_indexing_field.type.name}`."
              end

              f.resolve_with :apollo_entity_ref_paginated, source_ids_field: id_field_name_in_index, exposed_id_field: exposed_id_field

              yield f if block_given?
            end
          end
        end

        private

        # The set of options for a GraphQL-only field that has all abilities disabled. A field defined with these options
        # is available to be returned, but cannot be used for anything else (filtering, grouping, sorting, etc.).
        LIMITED_GRAPHQL_ONLY_FIELD_OPTIONS = {
          graphql_only: true,
          filterable: false,
          groupable: false,
          aggregatable: false,
          highlightable: false,
          sortable: false
        }

        # Like {LIMITED_GRAPHQL_ONLY_FIELD_OPTIONS} but for
        # {ElasticGraph::SchemaDefinition::SchemaElements::TypeWithSubfields#paginated_collection_field}.
        # It does not support the `sortable` option.
        LIMITED_GRAPHQL_ONLY_PAGINATED_FIELD_OPTIONS = LIMITED_GRAPHQL_ONLY_FIELD_OPTIONS.except(:sortable)

        def validate_entity_ref_options(method_name, field, id_field_name_in_index, entity_ref_type_name)
          # Defer validation since it depends on the definition of the entity ref type, which may be as yet undefined.
          schema_def_state.after_user_definition_complete do
            backing_indexing_field = field.backing_indexing_field # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field
            backing_indexing_field_type = backing_indexing_field.type.fully_unwrapped.name

            unless backing_indexing_field_type == "ID"
              raise Errors::SchemaError, "`#{field.parent_type.name}.#{field.name}` is invalid: `id_field_name_in_index` must " \
                "reference an `ID` field, but the type of `#{id_field_name_in_index}` is `#{backing_indexing_field_type}`."
            end

            entity_ref_type = schema_def_state.type_ref(entity_ref_type_name).fully_unwrapped.as_object_type
            unless entity_ref_type
              raise Errors::SchemaError, "`#{field.parent_type.name}.#{field.name}` is invalid: the referenced type " \
                "(`#{entity_ref_type_name}`) is not an object type as required by `#{method_name}`."
            end

            entity_ref_type_fields = entity_ref_type.graphql_fields_by_name.keys

            unless entity_ref_type_fields.size == 1
              raise Errors::SchemaError, "`#{field.parent_type.name}.#{field.name}` is invalid: `#{method_name}` can only be used " \
                "for types with a single field, but `#{entity_ref_type.name}` has #{entity_ref_type_fields.size} fields."
            end

            exposed_id_field = entity_ref_type_fields.first
            exposed_id_field_type = entity_ref_type.graphql_fields_by_name.fetch(exposed_id_field).type
            unless exposed_id_field_type.unwrap_non_null.name == "ID"
              raise Errors::SchemaError, "`#{field.parent_type.name}.#{field.name}` is invalid: `#{method_name}` can only be used for " \
                "types with a single `ID` field, but the type of `#{entity_ref_type.name}.#{exposed_id_field}` is `#{exposed_id_field_type.name}`."
            end

            yield exposed_id_field
          end
        end
      end
    end
  end
end
