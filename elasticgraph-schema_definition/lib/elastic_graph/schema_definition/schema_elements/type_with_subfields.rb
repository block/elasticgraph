# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/relation"
require "elastic_graph/schema_definition/indexing/field"
require "elastic_graph/schema_definition/indexing/field_type/object"
require "elastic_graph/schema_definition/mixins/can_be_graphql_only"
require "elastic_graph/schema_definition/mixins/has_derived_graphql_type_customizations"
require "elastic_graph/schema_definition/mixins/has_directives"
require "elastic_graph/schema_definition/mixins/has_documentation"
require "elastic_graph/schema_definition/mixins/has_type_info"
require "elastic_graph/schema_definition/mixins/supports_filtering_and_aggregation"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"
require "elastic_graph/schema_definition/schema_elements/list_counts_state"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Defines common functionality for all GraphQL types that have subfields:
      #
      # - {InputType}
      # - {InterfaceType}
      # - {ObjectType}
      #
      # @abstract
      #
      # @!attribute [rw] schema_kind
      #   @private
      # @!attribute [rw] schema_def_state
      #   @private
      # @!attribute [rw] type_ref
      #   @private
      # @!attribute [rw] reserved_field_names
      #   @private
      # @!attribute [rw] graphql_fields_by_name
      #   @private
      # @!attribute [rw] indexing_fields_by_name_in_index
      #   @private
      # @!attribute [rw] field_factory
      #   @private
      # @!attribute [rw] wrapping_type
      #   @private
      # @!attribute [rw] relay_pagination_type
      #   @private
      class TypeWithSubfields < Struct.new(
        :schema_kind, :schema_def_state, :type_ref, :reserved_field_names,
        :graphql_fields_by_name, :indexing_fields_by_name_in_index, :field_factory,
        :wrapping_type, :relay_pagination_type
      )
        prepend Mixins::VerifiesGraphQLName
        include Mixins::CanBeGraphQLOnly
        include Mixins::HasDocumentation
        include Mixins::HasDirectives
        include Mixins::HasDerivedGraphQLTypeCustomizations
        include Mixins::HasTypeInfo

        # The following methods are provided by `Struct.new`:
        # @dynamic type_ref

        # The following methods are provided by `SupportsFilteringAndAggregation`:
        # @dynamic derived_graphql_types

        # The following methods are provided by `CanBeGraphQLOnly`:
        # @dynamic graphql_only?

        # @private
        def initialize(schema_kind, schema_def_state, name, wrapping_type:, field_factory:)
          # `any_satisfy`, `any_of`/`all_of`, and `not` are "reserved" field names. They are reserved for usage by
          # ElasticGraph itself in the `*FilterInput` types it generates. If we allow them to be used as field
          # names, we'll run into conflicts when we later generate the `*FilterInput` type.
          #
          # Note that we don't have the same kind of conflict for the other filtering operators (e.g.
          # `equal_to_any_of`, `gt`, etc) because on the generated filter structure, those are leaf
          # nodes. They never exist alongside document field names on a filter type, but these do,
          # so we have to guard against them here.
          reserved_field_names = [
            schema_def_state.schema_elements.all_of,
            schema_def_state.schema_elements.any_of,
            schema_def_state.schema_elements.any_satisfy,
            schema_def_state.schema_elements.not
          ].to_set

          # @type var graphql_fields_by_name: ::Hash[::String, Field]
          graphql_fields_by_name = {}
          # @type var indexing_fields_by_name_in_index: ::Hash[::String, Field]
          indexing_fields_by_name_in_index = {}

          super(
            schema_kind,
            schema_def_state,
            schema_def_state.type_ref(name).to_final_form,
            reserved_field_names,
            graphql_fields_by_name,
            indexing_fields_by_name_in_index,
            field_factory,
            wrapping_type,
            false
          )

          yield self
        end

        # @return [String] the name of this GraphQL type
        def name
          type_ref.name
        end

        # Defines a [GraphQL field](https://spec.graphql.org/October2021/#sec-Language.Fields) on this type.
        #
        # @param name [String] name of the field
        # @param type [String] type of the field as a [type reference](https://spec.graphql.org/October2021/#sec-Type-References). The named type must be
        #   one of {BuiltInTypes ElasticGraph's built-in types} or a type that has been defined in your schema.
        # @param graphql_only [Boolean] if `true`, ElasticGraph will define the field as a GraphQL field but omit it from the indexing
        #   artifacts (`json_schemas.yaml` and `datastore_config.yaml`). This can be used along with `name_in_index` to support careful
        #   schema evolution.
        # @param indexing_only [Boolean] if `true`, ElasticGraph will define the field for indexing (in the `json_schemas.yaml` and
        #   `datastore_config.yaml` schema artifact) but will omit it from the GraphQL schema. This can be useful to begin indexing a field
        #   before you expose it in GraphQL so that you can fully backfill it first.
        # @option options [String] name_in_index the name of the field in the datastore index. Can be used to back a GraphQL field with a
        #   differently named field in the index.
        # @option options [String] singular can be used on a list field (e.g. `t.field "tags", "[String!]!", singular: "tag"`) to tell
        #   ElasticGraph what the singular form of a field's name is. When provided, ElasticGraph will define a `groupedBy` field (using the
        #   singular form) allowing clients to group by individual values from the field.
        # @option options [Boolean] aggregatable force-enables or disables the ability for aggregation queries to aggregate over this field.
        #   When not provided, ElasticGraph will infer field aggregatability based on the field's GraphQL type and mapping type.
        # @option options [Boolean] filterable force-enables or disables the ability for queries to filter by this field. When not provided,
        #   ElasticGraph will infer field filterability based on the field's GraphQL type and mapping type.
        # @option options [Boolean] groupable force-enables or disables the ability for aggregation queries to group by this field. When
        #   not provided, ElasticGraph will infer field groupability based on the field's GraphQL type and mapping type.
        # @option options [Boolean] sortable force-enables or disables the ability for queries to sort by this field. When not provided,
        #   ElasticGraph will infer field sortability based on the field's GraphQL type and mapping type.
        # @yield [Field] the field for further customization
        # @return [void]
        #
        # @see #paginated_collection_field
        # @see #relates_to_many
        # @see #relates_to_one
        #
        # @note Be careful about defining non-nullable fields. Changing a field’s type from non-nullable (e.g. `Int!`) to nullable (e.g.
        #   `Int`) is a breaking change for clients. Making a field non-nullable may also prevent you from applying permissioning to a field
        #   via an AuthZ layer (as such a layer would have no way to force a field value to `null` when for a client denied field access).
        #   Therefore, we recommend limiting your use of `!` to only a few situations such as defining a type’s primary key (e.g.
        #   `t.field "id", "ID!"`) or defining a list field (e.g. `t.field "authors", "[String!]!"`) since empty lists already provide a
        #   "no data" representation. You can still configure the ElasticGraph indexer to require a non-null value for a field using
        #   `f.json_schema nullable: false`.
        #
        # @note ElasticGraph’s understanding of datastore capabilities may override your configured
        #   `aggregatable`/`filterable`/`groupable`/`sortable` options. For example, a field indexed as `text` for full text search will
        #   not be sortable or groupable even if you pass `sortable: true, groupable: true` when defining the field, because [text fields
        #   cannot be efficiently sorted by or grouped on](https://www.elastic.co/guide/en/elasticsearch/reference/8.15/text.html#text).
        #
        # @example Define a field with documentation
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID" do |f|
        #         f.documentation "The Campaign's identifier."
        #       end
        #     end
        #   end
        #
        # @example Omit a new field from the GraphQL schema until its data has been backfilled
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #
        #       # TODO: remove `indexing_only: true` once the data for this field has been fully backfilled
        #       t.field "endDate", "Date", indexing_only: true
        #     end
        #   end
        #
        # @example Use `graphql_only` to introduce a new name for an existing field
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #
        #       t.field "endOn", "Date" do |f|
        #         f.directive "deprecated", reason: "Use `endDate` instead."
        #       end
        #
        #       # We've decided we want to call the field `endDate` instead of `endOn`, but the data
        #       # for this field is currently indexed in `endOn`, so we can use `graphql_only` and
        #       # `name_in_index` to expose the existing data under a new field name.
        #       t.field "endDate", "Date", name_in_index: "endOn", graphql_only: true
        #     end
        #   end
        def field(name, type, graphql_only: false, indexing_only: false, **options)
          if reserved_field_names.include?(name)
            raise Errors::SchemaError, "Invalid field name: `#{self.name}.#{name}`. `#{name}` is reserved for use by " \
              "ElasticGraph as a filtering operator. To use it for a field name, add " \
              "the `schema_element_name_overrides` option (on `ElasticGraph::SchemaDefinition::RakeTasks.new`) to " \
              "configure an alternate name for the `#{name}` operator."
          end

          field_factory.call(
            name: name,
            type: type,
            graphql_only: graphql_only,
            parent_type: wrapping_type,
            **options
          ) do |field|
            yield field if block_given?

            unless indexing_only
              register_field(field.name, field, graphql_fields_by_name, "GraphQL", :indexing_only)
            end

            unless graphql_only
              register_field(field.name_in_index, field, indexing_fields_by_name_in_index, "indexing", :graphql_only) do |f|
                f.to_indexing_field_reference
              end
            end
          end
        end

        # Registers the name of a field that existed in a prior version of the schema but has been deleted.
        #
        # @note In situations where this API applies, ElasticGraph will give you an error message indicating that you need to use this API
        #   or {Field#renamed_from}. Likewise, when ElasticGraph no longer needs to know about this, it'll give you a warning indicating
        #   the call to this method can be removed.
        #
        # @param field_name [String] name of field that used to exist but has been deleted
        # @return [void]
        #
        # @example Indicate that `Widget.description` has been deleted
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Widget" do |t|
        #       t.deleted_field "description"
        #     end
        #   end
        def deleted_field(field_name)
          schema_def_state.register_deleted_field(
            name,
            field_name,
            defined_at: caller_locations(2, 1).to_a.first, # : ::Thread::Backtrace::Location
            defined_via: %(type.deleted_field "#{field_name}")
          )
        end

        # Registers an old name that this type used to have in a prior version of the schema.
        #
        # @note In situations where this API applies, ElasticGraph will give you an error message indicating that you need to use this API
        #   or {API#deleted_type}. Likewise, when ElasticGraph no longer needs to know about this, it'll give you a warning indicating
        #   the call to this method can be removed.
        #
        # @param old_name [String] old name this field used to have in a prior version of the schema
        # @return [void]
        #
        # @example Indicate that `Widget` used to be called `Component`.
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Widget" do |t|
        #       t.renamed_from "Component"
        #     end
        #   end
        def renamed_from(old_name)
          schema_def_state.register_renamed_type(
            name,
            from: old_name,
            defined_at: caller_locations(2, 1).to_a.first, # : ::Thread::Backtrace::Location
            defined_via: %(type.renamed_from "#{old_name}")
          )
        end

        # An alternative to {#field} for when you have a list field that you want exposed as a [paginated Relay
        # connection](https://relay.dev/graphql/connections.htm) rather than as a simple list.
        #
        # @note Bear in mind that pagination does not have much efficiency benefit in this case: all elements of the collection will be
        #   retrieved when fetching this field from the datastore. The pagination implementation will just trim down the collection before
        #   returning it.
        #
        # @param name [String] name of the field
        # @param element_type [String] name of the type of element in the collection
        # @param name_in_index [String] the name of the field in the datastore index. Can be used to back a GraphQL field with a
        #   differently named field in the index.
        # @param singular [String] indicates what the singular form of a field's name is. When provided, ElasticGraph will define a
        #   `groupedBy` field (using the singular form) allowing clients to group by individual values from the field.
        # @yield [Field] the field for further customization
        # @return [void]
        #
        # @see #field
        # @see #relates_to_many
        # @see #relates_to_one
        #
        # @example Define `Author.books` as a paginated collection field
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Author" do |t|
        #       t.field "id", "ID"
        #       t.field "name", "String"
        #       t.paginated_collection_field "books", "String"
        #       t.index "authors"
        #     end
        #   end
        def paginated_collection_field(name, element_type, name_in_index: name, singular: nil, &block)
          element_type_ref = schema_def_state.type_ref(element_type).to_final_form
          element_type = element_type_ref.name

          schema_def_state.paginated_collection_element_types << element_type

          field(name, "[#{element_type}!]!", indexing_only: true, name_in_index: name_in_index, &block)

          field(
            name,
            element_type_ref.as_connection.name,
            name_in_index: name_in_index,
            type_for_derived_types: "[#{element_type}]",
            groupable: !!singular,
            sortable: false,
            graphql_only: true,
            singular: singular
          ) do |f|
            f.define_relay_pagination_arguments!
            block&.call(f)
          end
        end

        # Defines a "has one" relationship between the current indexed type and another indexed type by defining a field clients
        # can use to navigate across indexed types in a single GraphQL query.
        #
        # @param field_name [String] name of the relationship field
        # @param type [String] name of the related type
        # @param via [String] name of the foreign key field
        # @param dir [:in, :out] direction of the foreign key. Use `:in` for an inbound foreign key that resides on the related type and
        #   references the `id` of this type. Use `:out` for an outbound foreign key that resides on this type  and references the `id` of
        #   the related type.
        # @yield [Relationship] the generated relationship fields, for further customization
        # @return [void]
        #
        # @see #field
        # @see #relates_to_many
        #
        # @example Use `relates_to_one` to define `Player.team`
        #  ElasticGraph.define_schema do |schema|
        #    schema.object_type "Team" do |t|
        #      t.field "id", "ID"
        #      t.field "name", "String"
        #      t.field "homeCity", "String"
        #      t.index "teams"
        #    end
        #
        #    schema.object_type "Player" do |t|
        #      t.field "id", "ID"
        #      t.field "name", "String"
        #      t.relates_to_one "team", "Team", via: "teamId", dir: :out
        #      t.index "players"
        #    end
        #  end
        def relates_to_one(field_name, type, via:, dir:, &block)
          foreign_key_type = schema_def_state.type_ref(type).non_null? ? "ID!" : "ID"
          relates_to(field_name, type, via: via, dir: dir, foreign_key_type: foreign_key_type, cardinality: :one, related_type: type, &block)
        end

        # Defines a "has many" relationship between the current indexed type and another indexed type by defining a pair of fields clients
        # can use to navigate across indexed types in a single GraphQL query. The pair of generated fields will be [Relay Connection
        # types](https://relay.dev/graphql/connections.htm#sec-Connection-Types) allowing you to filter, sort, paginate, and aggregated the
        # related data.
        #
        # @param field_name [String] name of the relationship field
        # @param type [String] name of the related type
        # @param via [String] name of the foreign key field
        # @param dir [:in, :out] direction of the foreign key. Use `:in` for an inbound foreign key that resides on the related type and
        #   references the `id` of this type. Use `:out` for an outbound foreign key that resides on this type  and references the `id` of
        #   the related type.
        # @param singular [String] singular form of the `field_name`; will be used (along with an `Aggregations` suffix) for the name of
        #   the generated aggregations field
        # @yield [Relationship] the generated relationship fields, for further customization
        # @return [void]
        #
        # @see #field
        # @see #paginated_collection_field
        # @see #relates_to_one
        #
        # @example Use `relates_to_many` to define `Team.players` and `Team.playerAggregations`
        #  ElasticGraph.define_schema do |schema|
        #    schema.object_type "Team" do |t|
        #      t.field "id", "ID"
        #      t.field "name", "String"
        #      t.field "homeCity", "String"
        #      t.relates_to_many "players", "Player", via: "teamId", dir: :in, singular: "player"
        #      t.index "teams"
        #    end
        #
        #    schema.object_type "Player" do |t|
        #      t.field "id", "ID"
        #      t.field "name", "String"
        #      t.field "teamId", "ID"
        #      t.index "players"
        #    end
        #  end
        def relates_to_many(field_name, type, via:, dir:, singular:)
          foreign_key_type = (dir == :out) ? "[ID!]!" : "ID"
          type_ref = schema_def_state.type_ref(type).to_final_form

          relates_to(field_name, type_ref.as_connection.name, via: via, dir: dir, foreign_key_type: foreign_key_type, cardinality: :many, related_type: type) do |f|
            f.argument schema_def_state.schema_elements.filter, type_ref.as_filter_input.name do |a|
              a.documentation "Used to filter the returned `#{field_name}` based on the provided criteria."
            end

            f.argument schema_def_state.schema_elements.order_by, "[#{type_ref.as_sort_order.name}!]" do |a|
              a.documentation "Used to specify how the returned `#{field_name}` should be sorted."
            end

            f.define_relay_pagination_arguments!

            yield f if block_given?
          end

          aggregations_name = schema_def_state.schema_elements.normalize_case("#{singular}_aggregations")
          relates_to(aggregations_name, type_ref.as_aggregation.as_connection.name, via: via, dir: dir, foreign_key_type: foreign_key_type, cardinality: :many, related_type: type) do |f|
            f.argument schema_def_state.schema_elements.filter, type_ref.as_filter_input.name do |a|
              a.documentation "Used to filter the `#{type}` documents that get aggregated over based on the provided criteria."
            end

            f.define_relay_pagination_arguments!

            yield f if block_given?

            f.documentation f.derived_documentation("Aggregations over the `#{field_name}` data")
          end
        end

        # Converts the type to GraphQL SDL syntax.
        #
        # @private
        def to_sdl(&field_arg_selector)
          generate_sdl(name_section: name, &field_arg_selector)
        end

        # @private
        def generate_sdl(name_section:, &field_arg_selector)
          <<~SDL
            #{formatted_documentation}#{schema_kind} #{name_section} #{directives_sdl(suffix_with: " ")}{
              #{fields_sdl(&field_arg_selector)}
            }
          SDL
        end

        # @private
        def aggregated_values_type
          schema_def_state.type_ref("NonNumeric").as_aggregated_values
        end

        # @private
        def indexed?
          false
        end

        # @private
        def to_indexing_field_type
          Indexing::FieldType::Object.new(
            type_name: name,
            subfields: indexing_fields_by_name_in_index.values.map(&:to_indexing_field).compact,
            mapping_options: mapping_options,
            json_schema_options: json_schema_options
          )
        end

        # @private
        def current_sources
          indexing_fields_by_name_in_index.values.flat_map do |field|
            child_field_sources = field.type.fully_unwrapped.as_object_type&.current_sources || []
            [field.source&.relationship_name || SELF_RELATIONSHIP_NAME] + child_field_sources
          end
        end

        # @private
        def index_field_runtime_metadata_tuples(
          # path from the overall document root
          path_prefix: "",
          # the source of the parent field
          parent_source: SELF_RELATIONSHIP_NAME,
          # tracks the state of the list counts field
          list_counts_state: ListCountsState::INITIAL
        )
          indexing_fields_by_name_in_index.flat_map do |name, field|
            path = path_prefix + name
            source = field.source&.relationship_name || parent_source
            index_field = SchemaArtifacts::RuntimeMetadata::IndexField.new(source: source)

            list_count_field_tuples = field.paths_to_lists_for_count_indexing.map do |subpath|
              [list_counts_state.path_to_count_subfield(subpath), index_field] # : [::String, SchemaArtifacts::RuntimeMetadata::IndexField]
            end

            if (object_type = field.type.fully_unwrapped.as_object_type)
              new_list_counts_state =
                if field.type.list? && field.nested?
                  ListCountsState.new_list_counts_field(at: "#{path}.#{LIST_COUNTS_FIELD}")
                else
                  list_counts_state[name]
                end

              object_type.index_field_runtime_metadata_tuples(
                path_prefix: "#{path}.",
                parent_source: source,
                list_counts_state: new_list_counts_state
              )
            else
              [[path, index_field]] # : ::Array[[::String, SchemaArtifacts::RuntimeMetadata::IndexField]]
            end + list_count_field_tuples
          end
        end

        private

        def fields_sdl(&arg_selector)
          graphql_fields_by_name.values
            .map { |f| f.to_sdl(&arg_selector) }
            .flat_map { |sdl| sdl.split("\n") }
            .join("\n  ")
        end

        def register_field(name, field, registry, registry_type, only_option_to_fix, &to_comparable)
          if (existing_field = registry[name])
            field = Field.pick_most_accurate_from(field, existing_field, to_comparable: to_comparable || ->(f) { f }) do
              raise Errors::SchemaError, "Duplicate #{registry_type} field on Type #{self.name}: #{name}. " \
                "To resolve this, set `#{only_option_to_fix}: true` on one of the fields."
            end
          end

          registry[name] = field
        end

        def relates_to(field_name, type, via:, dir:, foreign_key_type:, cardinality:, related_type:)
          field(field_name, type, sortable: false, filterable: false, groupable: false, graphql_only: true) do |field|
            relationship = schema_def_state.factory.new_relationship(
              field,
              cardinality: cardinality,
              related_type: schema_def_state.type_ref(related_type).to_final_form,
              foreign_key: via,
              direction: dir
            )

            field.relationship = relationship
            field.resolver = :nested_relationships

            yield relationship if block_given?

            if dir == :out
              register_inferred_foreign_key_fields(from_type: [via, foreign_key_type], to_other: ["id", "ID!"], related_type: relationship.related_type)
            else
              register_inferred_foreign_key_fields(from_type: ["id", "ID!"], to_other: [via, foreign_key_type], related_type: relationship.related_type)
            end
          end
        end

        def register_inferred_foreign_key_fields(from_type:, to_other:, related_type:)
          # The root `Query` object shouldn't have inferred foreign key fields (it's not indexed).
          return if name.to_s == "Query"

          from_field_name, from_type_name = from_type
          field(from_field_name, from_type_name, indexing_only: true, accuracy_confidence: :medium)

          # If it's a self-referential, we also should add a foreign key field for the other end of the relation.
          if name == related_type.unwrap_non_null.name
            # This must be `:low` confidence for cases where we have a self-referential type that goes both
            # directions, such as:
            #
            # s.object_type "MyTypeBothDirections" do |t|
            #   t.relates_to_one "parent", "MyTypeBothDirections!", via: "children_ids", dir: :in
            #   t.relates_to_many "children", "MyTypeBothDirections", via: "children_ids", dir: :out
            # end
            #
            # In such a circumstance, the `from_type` side may be more accurate (and will be defined on the `field`
            # call above) and we want it preferred over this definition here.
            to_field_name, to_type_name = to_other
            field(to_field_name, to_type_name, indexing_only: true, accuracy_confidence: :low)
          end
        end
      end
    end
  end
end
