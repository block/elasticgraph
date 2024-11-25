# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/constants"
require "elastic_graph/schema_definition/indexing/field"
require "elastic_graph/schema_definition/indexing/field_reference"
require "elastic_graph/schema_definition/mixins/has_directives"
require "elastic_graph/schema_definition/mixins/has_documentation"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/mixins/has_type_info"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"
require "elastic_graph/support/graphql_formatter"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Represents a [GraphQL field](https://spec.graphql.org/October2021/#sec-Language.Fields).
      #
      # @example Define a GraphQL field
      #   ElasticGraph.define_schema do |schema|
      #     schema.object_type "Widget" do |t|
      #       t.field "id", "ID" do |f|
      #         # `f` in this block is a Field object
      #       end
      #     end
      #   end
      #
      # @!attribute [r] name
      #   @return [String] name of the field
      # @!attribute [r] schema_def_state
      #   @return [State] schema definition state
      # @!attribute [r] graphql_only
      #   @return [Boolean] true if this field exists only in the GraphQL schema and is not indexed
      # @!attribute [r] name_in_index
      #   @return [String] the name of this field in the datastore index
      #
      # @!attribute [rw] original_type
      #   @private
      # @!attribute [rw] parent_type
      #   @private
      # @!attribute [rw] original_type_for_derived_types
      #   @private
      # @!attribute [rw] accuracy_confidence
      #   @private
      # @!attribute [rw] filter_customizations
      #   @private
      # @!attribute [rw] grouped_by_customizations
      #   @private
      # @!attribute [rw] sub_aggregations_customizations
      #   @private
      # @!attribute [rw] aggregated_values_customizations
      #   @private
      # @!attribute [rw] sort_order_enum_value_customizations
      #   @private
      # @!attribute [rw] args
      #   @private
      # @!attribute [rw] sortable
      #   @private
      # @!attribute [rw] filterable
      #   @private
      # @!attribute [rw] aggregatable
      #   @private
      # @!attribute [rw] groupable
      #   @private
      # @!attribute [rw] source
      #   @private
      # @!attribute [rw] runtime_field_script
      #   @private
      # @!attribute [rw] relationship
      #   @private
      # @!attribute [rw] singular_name
      #   @private
      # @!attribute [rw] computation_detail
      #   @private
      # @!attribute [rw] non_nullable_in_json_schema
      #   @private
      # @!attribute [rw] backing_indexing_field
      #   @private
      # @!attribute [rw] as_input
      #   @private
      # @!attribute [rw] legacy_grouping_schema
      #   @private
      class Field < Struct.new(
        :name, :original_type, :parent_type, :original_type_for_derived_types, :schema_def_state, :accuracy_confidence,
        :filter_customizations, :grouped_by_customizations, :sub_aggregations_customizations,
        :aggregated_values_customizations, :sort_order_enum_value_customizations,
        :args, :sortable, :filterable, :aggregatable, :groupable, :graphql_only, :source, :runtime_field_script, :relationship, :singular_name,
        :computation_detail, :non_nullable_in_json_schema, :backing_indexing_field, :as_input,
        :legacy_grouping_schema, :name_in_index
      )
        include Mixins::HasDocumentation
        include Mixins::HasDirectives
        include Mixins::HasTypeInfo
        include Mixins::HasReadableToSAndInspect.new { |f| "#{f.parent_type.name}.#{f.name}: #{f.type}" }

        # @private
        def initialize(
          name:, type:, parent_type:, schema_def_state:,
          accuracy_confidence: :high, name_in_index: name,
          runtime_metadata_graphql_field: SchemaArtifacts::RuntimeMetadata::GraphQLField::EMPTY,
          type_for_derived_types: nil, graphql_only: nil, singular: nil,
          sortable: nil, filterable: nil, aggregatable: nil, groupable: nil,
          backing_indexing_field: nil, as_input: false, legacy_grouping_schema: false
        )
          type_ref = schema_def_state.type_ref(type)
          super(
            name: name,
            original_type: type_ref,
            parent_type: parent_type,
            original_type_for_derived_types: type_for_derived_types ? schema_def_state.type_ref(type_for_derived_types) : type_ref,
            schema_def_state: schema_def_state,
            accuracy_confidence: accuracy_confidence,
            filter_customizations: [],
            grouped_by_customizations: [],
            sub_aggregations_customizations: [],
            aggregated_values_customizations: [],
            sort_order_enum_value_customizations: [],
            args: {},
            sortable: sortable,
            filterable: filterable,
            aggregatable: aggregatable,
            groupable: groupable,
            graphql_only: graphql_only,
            source: nil,
            runtime_field_script: nil,
            # Note: we named the keyword argument `singular` (with no `_name` suffix) for consistency with
            # other schema definition APIs, which also use `singular:` instead of `singular_name:`. We include
            # the `_name` suffix on the attribute for clarity.
            singular_name: singular,
            name_in_index: name_in_index,
            non_nullable_in_json_schema: false,
            backing_indexing_field: backing_indexing_field,
            as_input: as_input,
            legacy_grouping_schema: legacy_grouping_schema
          )

          if name != name_in_index && name_in_index&.include?(".") && !graphql_only
            raise Errors::SchemaError, "#{self} has an invalid `name_in_index`: #{name_in_index.inspect}. Only `graphql_only: true` fields can have a `name_in_index` that references a child field."
          end

          schema_def_state.register_user_defined_field(self)
          yield self if block_given?
        end

        # @private
        @@initialize_param_names = instance_method(:initialize).parameters.map(&:last).to_set

        # must come after we capture the initialize params.
        prepend Mixins::VerifiesGraphQLName

        # @return [TypeReference] the type of this field
        def type
          # Here we lazily convert the `original_type` to an input type as needed. This must be lazy because
          # the logic of `as_input` depends on detecting whether the type is an enum type, which it may not
          # be able to do right away--we assume not if we can't tell, and retry every time this method is called.
          original_type.to_final_form(as_input: as_input)
        end

        # @return [TypeReference] the type of the corresponding field on derived types (usually this is the same as {#type}).
        #
        # @private
        def type_for_derived_types
          original_type_for_derived_types.to_final_form(as_input: as_input)
        end

        # @note For each field defined in your schema that is filterable, a corresponding filtering field will be created on the
        #   `*FilterInput` type derived from the parent object type.
        #
        # Registers a customization callback that will be applied to the corresponding filtering field that will be generated for this
        # field.
        #
        # @yield [Field] derived filtering field
        # @return [void]
        # @see #customize_aggregated_values_field
        # @see #customize_grouped_by_field
        # @see #customize_sort_order_enum_values
        # @see #customize_sub_aggregations_field
        # @see #on_each_generated_schema_element
        #
        # @example Mark `CampaignFilterInput.organizationId` with `@deprecated`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #
        #       t.field "organizationId", "ID" do |f|
        #         f.customize_filter_field do |ff|
        #           ff.directive "deprecated"
        #         end
        #       end
        #
        #       t.index "campaigns"
        #     end
        #   end
        def customize_filter_field(&customization_block)
          filter_customizations << customization_block
        end

        # @note For each field defined in your schema that is aggregatable, a corresponding `aggregatedValues` field will be created on the
        #   `*AggregatedValues` type derived from the parent object type.
        #
        # Registers a customization callback that will be applied to the corresponding `aggregatedValues` field that will be generated for
        # this field.
        #
        # @yield [Field] derived aggregated values field
        # @return [void]
        # @see #customize_filter_field
        # @see #customize_grouped_by_field
        # @see #customize_sort_order_enum_values
        # @see #customize_sub_aggregations_field
        # @see #on_each_generated_schema_element
        #
        # @example Mark `CampaignAggregatedValues.adImpressions` with `@deprecated`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #
        #       t.field "adImpressions", "Int" do |f|
        #         f.customize_aggregated_values_field do |avf|
        #           avf.directive "deprecated"
        #         end
        #       end
        #
        #       t.index "campaigns"
        #     end
        #   end
        def customize_aggregated_values_field(&customization_block)
          aggregated_values_customizations << customization_block
        end

        # @note For each field defined in your schema that is groupable, a corresponding `groupedBy` field will be created on the
        #   `*AggregationGroupedBy` type derived from the parent object type.
        #
        # Registers a customization callback that will be applied to the corresponding `groupedBy` field that will be generated for this
        # field.
        #
        # @yield [Field] derived grouped by field
        # @return [void]
        # @see #customize_aggregated_values_field
        # @see #customize_filter_field
        # @see #customize_sort_order_enum_values
        # @see #customize_sub_aggregations_field
        # @see #on_each_generated_schema_element
        #
        # @example Mark `CampaignGroupedBy.organizationId` with `@deprecated`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #
        #       t.field "organizationId", "ID" do |f|
        #         f.customize_grouped_by_field do |gbf|
        #           gbf.directive "deprecated"
        #         end
        #       end
        #
        #       t.index "campaigns"
        #     end
        #   end
        def customize_grouped_by_field(&customization_block)
          grouped_by_customizations << customization_block
        end

        # @note For each field defined in your schema that is sub-aggregatable (e.g. list fields indexed using the `nested` mapping type),
        # a corresponding field will be created on the `*AggregationSubAggregations` type derived from the parent object type.
        #
        # Registers a customization callback that will be applied to the corresponding `subAggregations` field that will be generated for
        # this field.
        #
        # @yield [Field] derived sub-aggregations field
        # @return [void]
        # @see #customize_aggregated_values_field
        # @see #customize_filter_field
        # @see #customize_grouped_by_field
        # @see #customize_sort_order_enum_values
        # @see #on_each_generated_schema_element
        #
        # @example Mark `TransactionAggregationSubAggregations.fees` with `@deprecated`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Transaction" do |t|
        #       t.field "id", "ID"
        #
        #       t.field "fees", "[Money!]!" do |f|
        #         f.mapping type: "nested"
        #
        #         f.customize_sub_aggregations_field do |saf|
        #           # Adds a `@deprecated` directive to the `PaymentAggregationSubAggregations.fees`
        #           # field without also adding it to the `Payment.fees` field.
        #           saf.directive "deprecated"
        #         end
        #       end
        #
        #       t.index "transactions"
        #     end
        #
        #     schema.object_type "Money" do |t|
        #       t.field "amount", "Int"
        #       t.field "currency", "String"
        #     end
        #   end
        def customize_sub_aggregations_field(&customization_block)
          sub_aggregations_customizations << customization_block
        end

        # @note for each sortable field, enum values will be generated on the derived sort order enum type allowing you to
        #   sort by the field `ASC` or `DESC`.
        #
        # Registers a customization callback that will be applied to the corresponding enum values that will be generated for this field
        # on the derived `SortOrder` enum type.
        #
        # @yield [SortOrderEnumValue] derived sort order enum value
        # @return [void]
        # @see #customize_aggregated_values_field
        # @see #customize_filter_field
        # @see #customize_grouped_by_field
        # @see #customize_sub_aggregations_field
        # @see #on_each_generated_schema_element
        #
        # @example Mark `CampaignSortOrder.organizationId_(ASC|DESC)` with `@deprecated`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #
        #       t.field "organizationId", "ID" do |f|
        #         f.customize_sort_order_enum_values do |soev|
        #           soev.directive "deprecated"
        #         end
        #       end
        #
        #       t.index "campaigns"
        #     end
        #   end
        def customize_sort_order_enum_values(&customization_block)
          sort_order_enum_value_customizations << customization_block
        end

        # When you define a {Field} on an {ObjectType} or {InterfaceType}, ElasticGraph generates up to 6 different GraphQL schema elements
        # for it:
        #
        # * A {Field} is generated on the parent {ObjectType} or {InterfaceType} (that is, this field itself). This is used by clients to
        #   ask for values for the field in a response.
        # * A {Field} may be generated on the `*FilterInput` {InputType} derived from the parent {ObjectType} or {InterfaceType}. This is
        #   used by clients to specify how the query should filter.
        # * A {Field} may be generated on the `*AggregationGroupedBy` {ObjectType} derived from the parent {ObjectType} or {InterfaceType}.
        #   This is used by clients to specify how aggregations should be grouped.
        # * A {Field} may be generated on the `*AggregatedValues` {ObjectType} derived from the parent {ObjectType} or {InterfaceType}.
        #   This is used by clients to apply aggregation functions (e.g. `sum`, `max`, `min`, etc) to a set of field values for a group.
        # * A {Field} may be generated on the `*AggregationSubAggregations` {ObjectType} derived from the parent {ObjectType} or
        #   {InterfaceType}. This is used by clients to perform sub-aggregations on list fields indexed using the `nested` mapping type.
        # * Multiple {EnumValue}s (both `*_ASC` and `*_DESC`) are generated on the `*SortOrder` {EnumType} derived from the parent indexed
        #   {ObjectType}. This is used by clients to sort by a field.
        #
        # This method registers a customization callback which is applied to every element that is generated for this field.
        #
        # @yield [Field, EnumValue] the schema element
        # @return [void]
        # @see #customize_aggregated_values_field
        # @see #customize_filter_field
        # @see #customize_grouped_by_field
        # @see #customize_sort_order_enum_values
        # @see #customize_sub_aggregations_field
        #
        # @example
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Transaction" do |t|
        #       t.field "id", "ID"
        #
        #       t.field "amount", "Int" do |f|
        #         f.on_each_generated_schema_element do |element|
        #           # Adds a `@deprecated` directive to every GraphQL schema element generated for `amount`:
        #           #
        #           # - The `Transaction.amount` field.
        #           # - The `TransactionFilterInput.amount` field.
        #           # - The `TransactionAggregationGroupedBy.amount` field.
        #           # - The `TransactionAggregatedValues.amount` field.
        #           # - The `TransactionSortOrder.amount_ASC` and`TransactionSortOrder.amount_DESC` enum values.
        #           element.directive "deprecated"
        #         end
        #       end
        #
        #       t.index "transactions"
        #     end
        #   end
        def on_each_generated_schema_element(&customization_block)
          customization_block.call(self)
          customize_filter_field(&customization_block)
          customize_aggregated_values_field(&customization_block)
          customize_grouped_by_field(&customization_block)
          customize_sub_aggregations_field(&customization_block)
          customize_sort_order_enum_values(&customization_block)
        end

        # (see Mixins::HasTypeInfo#json_schema)
        def json_schema(nullable: nil, **options)
          if options.key?(:type)
            raise Errors::SchemaError, "Cannot override JSON schema type of field `#{name}` with `#{options.fetch(:type)}`"
          end

          case nullable
          when true
            raise Errors::SchemaError, "`nullable: true` is not allowed on a field--just declare the GraphQL field as being nullable (no `!` suffix) instead."
          when false
            self.non_nullable_in_json_schema = true
          end

          super(**options)
        end

        # Configures ElasticGraph to source a field’s value from a related object. This can be used to denormalize data at ingestion time to
        # support filtering, grouping, sorting, or aggregating data on a field from a related object.
        #
        # @param relationship [String] name of a relationship defined with {TypeWithSubfields#relates_to_one} using an inbound foreign key
        #   which contains the the field you wish to source values from
        # @param field_path [String] dot-separated path to the field on the related type containing values that should be copied to this
        #   field
        # @return [void]
        #
        # @example Source `City.currency` from `Country.currency`
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Country" do |t|
        #       t.field "id", "ID"
        #       t.field "name", "String"
        #       t.field "currency", "String"
        #       t.relates_to_one "capitalCity", "City", via: "capitalCityId", dir: :out
        #       t.index "countries"
        #     end
        #
        #     schema.object_type "City" do |t|
        #       t.field "id", "ID"
        #       t.field "name", "String"
        #       t.relates_to_one "capitalOf", "Country", via: "capitalCityId", dir: :in
        #
        #       t.field "currency", "String" do |f|
        #         f.sourced_from "capitalOf", "currency"
        #       end
        #
        #       t.index "cities"
        #     end
        #   end
        def sourced_from(relationship, field_path)
          self.source = schema_def_state.factory.new_field_source(
            relationship_name: relationship,
            field_path: field_path
          )
        end

        # @private
        def runtime_script(script)
          self.runtime_field_script = script
        end

        # Registers an old name that this field used to have in a prior version of the schema.
        #
        # @note In situations where this API applies, ElasticGraph will give you an error message indicating that you need to use this API
        #   or {TypeWithSubfields#deleted_field}. Likewise, when ElasticGraph no longer needs to know about this, it'll give you a warning
        #   indicating the call to this method can be removed.
        #
        # @param old_name [String] old name this field used to have in a prior version of the schema
        # @return [void]
        #
        # @example Indicate that `Widget.description` used to be called `Widget.notes`.
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Widget" do |t|
        #       t.field "description", "String" do |f|
        #         f.renamed_from "notes"
        #       end
        #     end
        #   end
        def renamed_from(old_name)
          schema_def_state.register_renamed_field(
            parent_type.name,
            from: old_name,
            to: name,
            defined_at: caller_locations(1, 1).first, # : ::Thread::Backtrace::Location
            defined_via: %(field.renamed_from "#{old_name}")
          )
        end

        # @private
        def to_sdl(type_structure_only: false, default_value_sdl: nil, &arg_selector)
          if type_structure_only
            "#{name}#{args_sdl(joiner: ", ", &arg_selector)}: #{type.name}"
          else
            args_sdl = args_sdl(joiner: "\n  ", after_opening_paren: "\n  ", &arg_selector)
            "#{formatted_documentation}#{name}#{args_sdl}: #{type.name}#{default_value_sdl} #{directives_sdl}".strip
          end
        end

        # Indicates if this field is sortable. Sortable fields will have corresponding `_ASC` and `_DESC` values generated in the
        # sort order {EnumType} of the parent indexed type.
        #
        # By default, the sortability is inferred by the field type and mapping. For example, list fields are not sortable,
        # and fields mapped as `text` are not sortable either. Fields are sortable in most other cases.
        #
        # The `sortable: true` option can be used to force a field to be sortable.
        #
        # @return [Boolean] true if this field is sortable
        def sortable?
          return sortable unless sortable.nil?

          # List fields are not sortable by default. We'd need to provide the datastore a sort mode option:
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/sort-search-results.html#_sort_mode_option
          return false if type.list?

          # Boolean fields are not sortable by default.
          #   - Boolean: sorting all falses before all trues (or whatever) is not generally interesting.
          return false if type.unwrap_non_null.boolean?

          # Elasticsearch/OpenSearch do not support sorting text fields:
          # > Text fields are not used for sorting...
          # (from https://www.elastic.co/guide/en/elasticsearch/reference/current/the datastore.html#text)
          return false if text?

          # If the type uses custom mapping type we don't know how if the datastore can sort by it, so we assume it's not sortable.
          return false if type.as_object_type&.has_custom_mapping_type?

          # Default every other field to being sortable.
          true
        end

        # Indicates if this field is filterable. Filterable fields will be available in the GraphQL schema under the `filter` argument.
        #
        # Most fields are filterable, except when:
        #
        # - It's a relation. Relation fields require us to load the related data from another index and can't be filtered on.
        # - The field is an object type that isn't itself filterable (e.g. due to having no filterable fields or whatever).
        # - Explicitly disabled with `filterable: false`.
        #
        # @return [Boolean]
        def filterable?
          # Object types that use custom index mappings (as `GeoLocation` does) aren't filterable
          # by default since we can't guess what datastore filtering capabilities they have. We've implemented
          # filtering support for `GeoLocation` fields, though, so we need to explicitly make it fliterable here.
          # TODO: clean this up using an interface instead of checking for `GeoLocation`.
          return true if type.fully_unwrapped.name == "GeoLocation"

          return false if relationship || type.fully_unwrapped.as_object_type&.does_not_support?(&:filterable?)
          return true if filterable.nil?
          filterable
        end

        # Indicates if this field is groupable. Groupable fields will be available under `groupedBy` for an aggregations query.
        #
        # Groupability is inferred based on the field type and mapping type, or you can use the `groupable: true` option to force it.
        #
        # @return [Boolean]
        def groupable?
          # If the groupability of the field was specified explicitly when the field was defined, use the specified value.
          return groupable unless groupable.nil?

          # We don't want the `id` field of an indexed type to be available to group by, because it's the unique primary key
          # and the groupings would each contain one document. It's simpler and more efficient to just query the raw documents
          # instead.
          return false if parent_type.indexed? && name == "id"

          return false if relationship || type.fully_unwrapped.as_object_type&.does_not_support?(&:groupable?)

          # We don't support grouping an entire list of values, but we do support grouping on individual values in a list.
          # However, we only do so when a `singular_name` has been provided (so that we know what to call the grouped_by field).
          # The semantics are a little odd (since one document can be duplicated in multiple grouping buckets) so we're ok
          # with not offering it by default--the user has to opt-in by telling us what to call the field in its singular form.
          return list_field_groupable_by_single_values? if type.list? && type.fully_unwrapped.leaf?

          # Nested fields will be supported through specific nested aggregation support, and do not
          # work as expected when grouping on the root document type.
          return false if nested?

          # Text fields cannot be efficiently grouped on, so make them non-groupable by default.
          return false if text?

          # In all other cases, default to being groupable.
          true
        end

        # Indicates if this field is aggregatable. Aggregatable fields will be available under `aggregatedValues` for an aggregations query.
        #
        # Aggregatability is inferred based on the field type and mapping type, or you can use the `aggregatable: true` option to force it.
        #
        # @return [Boolean]
        def aggregatable?
          return aggregatable unless aggregatable.nil?
          return false if relationship

          # We don't yet support aggregating over subfields of a `nested` field.
          # TODO: add support for aggregating over subfields of `nested` fields.
          return false if nested?

          # Text fields are not efficiently aggregatable (and you'll often get errors from the datastore if you attempt to aggregate them).
          return false if text?

          type_for_derived_types.fully_unwrapped.as_object_type&.supports?(&:aggregatable?) || index_leaf?
        end

        # Indicates if this field can be used as the basis for a sub-aggregation. Sub-aggregatable fields will be available under
        # `subAggregations` for an aggregations query.
        #
        # Only nested fields, and object fields which have nested fields, can be sub-aggregated.
        #
        # @return [Boolean]
        def sub_aggregatable?
          return false if relationship

          nested? || type_for_derived_types.fully_unwrapped.as_object_type&.supports?(&:sub_aggregatable?)
        end

        # Defines an argument on the field.
        #
        # @note ElasticGraph takes care of defining arguments for all the query features it supports, so there is generally no need to use
        #   this API, and it has no way to interpret arbitrary arguments defined on a field. However, it can be useful for extensions that
        #   extend the {ElasticGraph::GraphQL} query engine. For example, {ElasticGraph::Apollo} uses this API to satisfy the [Apollo
        #   federation subgraph spec](https://www.apollographql.com/docs/federation/federation-spec/).
        #
        # @param name [String] name of the argument
        # @param value_type [String] type of the argument in GraphQL SDL syntax
        # @yield [Argument] for further customization
        #
        # @example Define an argument on a field
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Product" do |t|
        #       t.field "name", "String" do |f|
        #         f.argument "language", "String"
        #       end
        #     end
        #   end
        def argument(name, value_type, &block)
          args[name] = schema_def_state.factory.new_argument(
            self,
            name,
            schema_def_state.type_ref(value_type),
            &block
          )
        end

        # The index mapping type in effect for this field. This could come from either the field definition or from the type definition.
        #
        # @return [String]
        def mapping_type
          backing_indexing_field&.mapping_type || (resolve_mapping || {})["type"]
        end

        # @private
        def list_field_groupable_by_single_values?
          (type.list? || backing_indexing_field&.type&.list?) && !singular_name.nil?
        end

        # @private
        def define_aggregated_values_field(parent_type)
          return unless aggregatable?

          unwrapped_type_for_derived_types = type_for_derived_types.fully_unwrapped
          aggregated_values_type =
            if index_leaf?
              unwrapped_type_for_derived_types.resolved.aggregated_values_type
            else
              unwrapped_type_for_derived_types.as_aggregated_values
            end

          parent_type.field name, aggregated_values_type.name, name_in_index: name_in_index, graphql_only: true do |f|
            f.documentation derived_documentation("Computed aggregate values for the `#{name}` field")
            aggregated_values_customizations.each { |block| block.call(f) }
          end
        end

        # @private
        def define_grouped_by_field(parent_type)
          return unless (field_name = grouped_by_field_name)

          parent_type.field field_name, grouped_by_field_type_name, name_in_index: name_in_index, graphql_only: true do |f|
            add_grouped_by_field_documentation(f)

            define_legacy_timestamp_grouping_arguments_if_needed(f) if legacy_grouping_schema

            grouped_by_customizations.each { |block| block.call(f) }
          end
        end

        # @private
        def grouped_by_field_type_name
          unwrapped_type = type_for_derived_types.fully_unwrapped
          if unwrapped_type.scalar_type_needing_grouped_by_object? && !legacy_grouping_schema
            unwrapped_type.with_reverted_override.as_grouped_by.name
          elsif unwrapped_type.leaf?
            unwrapped_type.name
          else
            unwrapped_type.as_grouped_by.name
          end
        end

        # @private
        def add_grouped_by_field_documentation(field)
          text = if list_field_groupable_by_single_values?
            derived_documentation(
              "The individual value from `#{name}` for this group",
              list_field_grouped_by_doc_note("`#{name}`")
            )
          elsif type.list? && type.fully_unwrapped.object?
            derived_documentation(
              "The `#{name}` field value for this group",
              list_field_grouped_by_doc_note("the selected subfields of `#{name}`")
            )
          elsif type_for_derived_types.fully_unwrapped.scalar_type_needing_grouped_by_object? && !legacy_grouping_schema
            derived_documentation("Offers the different grouping options for the `#{name}` value within this group")
          else
            derived_documentation("The `#{name}` field value for this group")
          end

          field.documentation text
        end

        # @private
        def grouped_by_field_name
          return nil unless groupable?
          list_field_groupable_by_single_values? ? singular_name : name
        end

        # @private
        def define_sub_aggregations_field(parent_type:, type:)
          parent_type.field name, type, name_in_index: name_in_index, graphql_only: true do |f|
            f.documentation derived_documentation("Used to perform a sub-aggregation of `#{name}`")
            sub_aggregations_customizations.each { |c| c.call(f) }

            yield f if block_given?
          end
        end

        # @private
        def to_filter_field(parent_type:, for_single_value: !type_for_derived_types.list?)
          type_prefix = text? ? "Text" : type_for_derived_types.fully_unwrapped.name
          filter_type = schema_def_state
            .type_ref(type_prefix)
            .as_static_derived_type(filter_field_category(for_single_value))
            .name

          params = to_h
            .slice(*@@initialize_param_names)
            .merge(type: filter_type, parent_type: parent_type, name_in_index: name_in_index, type_for_derived_types: nil)

          schema_def_state.factory.new_field(**params).tap do |f|
            f.documentation derived_documentation(
              "Used to filter on the `#{name}` field",
              "When `null` or an empty object is passed, matches all documents"
            )

            filter_customizations.each { |c| c.call(f) }
          end
        end

        # @private
        def define_relay_pagination_arguments!
          argument schema_def_state.schema_elements.first.to_sym, "Int" do |a|
            a.documentation <<~EOS
              Used in conjunction with the `after` argument to forward-paginate through the `#{name}`.
              When provided, limits the number of returned results to the first `n` after the provided
              `after` cursor (or from the start of the `#{name}`, if no `after` cursor is provided).

              See the [Relay GraphQL Cursor Connections
              Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
            EOS
          end

          argument schema_def_state.schema_elements.after.to_sym, "Cursor" do |a|
            a.documentation <<~EOS
              Used to forward-paginate through the `#{name}`. When provided, the next page after the
              provided cursor will be returned.

              See the [Relay GraphQL Cursor Connections
              Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
            EOS
          end

          argument schema_def_state.schema_elements.last.to_sym, "Int" do |a|
            a.documentation <<~EOS
              Used in conjunction with the `before` argument to backward-paginate through the `#{name}`.
              When provided, limits the number of returned results to the last `n` before the provided
              `before` cursor (or from the end of the `#{name}`, if no `before` cursor is provided).

              See the [Relay GraphQL Cursor Connections
              Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
            EOS
          end

          argument schema_def_state.schema_elements.before.to_sym, "Cursor" do |a|
            a.documentation <<~EOS
              Used to backward-paginate through the `#{name}`. When provided, the previous page before the
              provided cursor will be returned.

              See the [Relay GraphQL Cursor Connections
              Specification](https://relay.dev/graphql/connections.htm#sec-Arguments) for more info.
            EOS
          end
        end

        # Converts this field to an `Indexing::FieldReference`, which contains all the attributes involved
        # in building an `Indexing::Field`. Notably, we cannot actually convert to an `Indexing::Field` at
        # the point this method is called, because the referenced field type may not have been defined
        # yet. We don't need an actual `Indexing::Field` until the very end of the schema definition process,
        # when we are dumping the artifacts. However, we need this at field definition time so that we
        # can correctly detect duplicate indexing field issues when a field is defined. (This is used
        # in `TypeWithSubfields#field`).
        #
        # @private
        def to_indexing_field_reference
          return nil if graphql_only

          Indexing::FieldReference.new(
            name: name,
            name_in_index: name_in_index,
            type: non_nullable_in_json_schema ? type.wrap_non_null : type,
            mapping_options: mapping_options,
            json_schema_options: json_schema_options,
            accuracy_confidence: accuracy_confidence,
            source: source,
            runtime_field_script: runtime_field_script
          )
        end

        # Converts this field to its `IndexingField` form.
        #
        # @private
        def to_indexing_field
          to_indexing_field_reference&.resolve
        end

        # @private
        def resolve_mapping
          to_indexing_field&.mapping
        end

        # Returns the string paths to the list fields that we need to index counts for.
        # We do this to support the ability to filter on the size of a list.
        #
        # @private
        def paths_to_lists_for_count_indexing(has_list_ancestor: false)
          self_path = (has_list_ancestor || type.list?) ? [name_in_index] : []

          nested_paths =
            # Nested fields get indexed as separate hidden documents:
            # https://www.elastic.co/guide/en/elasticsearch/reference/8.8/nested.html
            #
            # Given that, the counts of any `nested` list subfields will go in a `__counts` field on the
            # separate hidden document.
            if !nested? && (object_type = type.fully_unwrapped.as_object_type)
              object_type.indexing_fields_by_name_in_index.values.flat_map do |sub_field|
                sub_field.paths_to_lists_for_count_indexing(has_list_ancestor: has_list_ancestor || type.list?).map do |sub_path|
                  "#{name_in_index}#{LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR}#{sub_path}"
                end
              end
            else
              []
            end

          self_path + nested_paths
        end

        # Indicates if this field is a leaf value in the index.  Note that GraphQL leaf values
        # are always leaf values in the index but the inverse is not always true. For example,
        # a `GeoLocation` field is not a leaf in GraphQL (because `GeoLocation` is an object
        # type with subfields) but in the index we use a single `geo_point` mapping type, which
        # is a single unit, so we consider it an index leaf.
        #
        # @private
        def index_leaf?
          type_for_derived_types.fully_unwrapped.leaf? || DATASTORE_PROPERTYLESS_OBJECT_TYPES.include?(mapping_type)
        end

        # @private
        ACCURACY_SCORES = {
          # :high is assigned to `Field`s that are generated directly from GraphQL fields or :extra_fields.
          # For these, we know everything available to us in the schema about them.
          high: 3,

          # :medium is assigned to `Field`s that are inferred from the id fields required by a relation.
          # We make logical guesses about the `indexing_field_type` but if the field is also manually defined,
          # it could be slightly different (e.g. additional json schema validations), so we have medium
          # confidence of these.
          medium: 2,

          # :low is assigned to the ElastcField inferred for the foreign key of an inbound relation. The
          # nullability/cardinality of the foreign key field cannot be known from the relation metadata,
          # so we just guess what seems safest (`[:nullable]`). If the field is defined another way
          # we should prefer it, so we give these fields :low confidence.
          low: 1
        }

        # Given two fields, picks the one that is most accurate. If they have the same accuracy
        # confidence, yields to a block to force it to deal with the discrepancy, unless the fields
        # are exactly equal (in which case we can return either).
        #
        # @private
        def self.pick_most_accurate_from(field1, field2, to_comparable: ->(it) { it })
          return field1 if to_comparable.call(field1) == to_comparable.call(field2)
          yield if field1.accuracy_confidence == field2.accuracy_confidence
          # Array#max_by can return nil (when called on an empty array), but our steep type is non-nil.
          # Since it's not smart enough to realize the non-empty-array-usage of `max_by` won't return nil,
          # we have to cast it to untyped here.
          _ = [field1, field2].max_by { |f| ACCURACY_SCORES.fetch(f.accuracy_confidence) }
        end

        # Indicates if the field uses the `nested` mapping type.
        #
        # @private
        def nested?
          mapping_type == "nested"
        end

        # Records the `ComputationDetail` that should be on the `runtime_metadata_graphql_field`.
        #
        # @private
        def runtime_metadata_computation_detail(empty_bucket_value:, function:)
          self.computation_detail = SchemaArtifacts::RuntimeMetadata::ComputationDetail.new(
            empty_bucket_value: empty_bucket_value,
            function: function
          )
        end

        # Lazily creates and returns a GraphQLField using the field's {#name_in_index}, {#computation_detail},
        # and {#relationship}.
        #
        # @private
        def runtime_metadata_graphql_field
          SchemaArtifacts::RuntimeMetadata::GraphQLField.new(
            name_in_index: name_in_index,
            computation_detail: computation_detail,
            relation: relationship&.runtime_metadata
          )
        end

        private

        def args_sdl(joiner:, after_opening_paren: "", &arg_selector)
          selected_args = args.values.select(&arg_selector)
          args_sdl = selected_args.map(&:to_sdl).flat_map { |s| s.split("\n") }.join(joiner)
          return nil if args_sdl.empty?
          "(#{after_opening_paren}#{args_sdl})"
        end

        # Indicates if the field uses the `text` mapping type.
        def text?
          mapping_type == "text"
        end

        def define_legacy_timestamp_grouping_arguments_if_needed(grouping_field)
          case type.fully_unwrapped.name
          when "Date"
            grouping_field.argument schema_def_state.schema_elements.granularity, "DateGroupingGranularity!" do |a|
              a.documentation "Determines the grouping granularity for this field."
            end

            grouping_field.argument schema_def_state.schema_elements.offset_days, "Int" do |a|
              a.documentation <<~EOS
                Number of days (positive or negative) to shift the `Date` boundaries of each date grouping bucket.

                For example, when grouping by `YEAR`, this can be used to align the buckets with fiscal or school years instead of calendar years.
              EOS
            end
          when "DateTime"
            grouping_field.argument schema_def_state.schema_elements.granularity, "DateTimeGroupingGranularity!" do |a|
              a.documentation "Determines the grouping granularity for this field."
            end

            grouping_field.argument schema_def_state.schema_elements.time_zone, "TimeZone" do |a|
              a.documentation "The time zone to use when determining which grouping a `DateTime` value falls in."
              a.default "UTC"
            end

            grouping_field.argument schema_def_state.schema_elements.offset, "DateTimeGroupingOffsetInput" do |a|
              a.documentation <<~EOS
                Amount of offset (positive or negative) to shift the `DateTime` boundaries of each grouping bucket.

                For example, when grouping by `WEEK`, you can shift by 24 hours to change what day-of-week weeks are considered to start on.
              EOS
            end
          end
        end

        def list_field_grouped_by_doc_note(individual_value_selection_description)
          <<~EOS.strip
            Note: `#{name}` is a collection field, but selecting this field will group on individual values of #{individual_value_selection_description}.
            That means that a document may be grouped into multiple aggregation groupings (i.e. when its `#{name}`
            field has multiple values) leading to some data duplication in the response. However, if a value shows
            up in `#{name}` multiple times for a single document, that document will only be included in the group
            once
          EOS
        end

        # Determines the suffix of the filter field derived for this field. The suffix used determines
        # the filtering capabilities (e.g. filtering on a single value vs a list of values with `any_satisfy`).
        def filter_field_category(for_single_value)
          return :filter_input if for_single_value

          # For an index leaf field, there are no further nesting paths to traverse. We want to directly
          # use a `ListFilterInput` type (e.g. `IntListFilterInput`) to offer `any_satisfy` filtering at this level.
          return :list_filter_input if index_leaf?

          # If it's a list-of-objects field we require the user to tell us what mapping type they want to
          # use, which determines the suffix (and is handled below). Otherwise, we want to use `FieldsListFilterInput`.
          # We are within a list filtering context (as indicated by `for_single_value` being false) without
          # being at an index leaf field, so we must use `FieldsListFilterInput` as there are further nesting paths
          # on the document and we want to provide `any_satisfy` at the leaf fields.
          return :fields_list_filter_input unless type_for_derived_types.list?

          case mapping_type
          when "nested" then :list_filter_input
          when "object" then :fields_list_filter_input
          else
            raise Errors::SchemaError, <<~EOS
              `#{parent_type.name}.#{name}` is a list-of-objects field, but the mapping type has not been explicitly specified. Elasticsearch and OpenSearch
              offer two ways to index list-of-objects fields. It cannot be changed on an existing field without dropping the index and recreating it (losing
              any existing indexed data!), and there are nuanced tradeoffs involved here, so ElasticGraph provides no default mapping in this situation.

              If you're currently prototyping and don't want to spend time weighing this tradeoff, we recommend you do this:

              ```
              t.field "#{name}", "#{type.name}" do |f|
                # Here we are opting for flexibility (nested) over pure performance (object).
                # TODO: evaluate if we want to stick with `nested` before going to production.
                f.mapping type: "nested"
              end
              ```

              Read on for details of the tradeoff involved here.

              -----------------------------------------------------------------------------------------------------------------------------

              Here are the options:

              1) `f.mapping type: "object"` will cause each field path to be indexed as a separate "flattened" list.

              For example, given a `Film` document like this:

              ```
              {
                "name": "The Empire Strikes Back",
                "characters": [
                  {"first": "Luke", "last": "Skywalker"},
                  {"first": "Han", "last": "Solo"}
                ]
              }
              ```

              ...the data will look like this in the inverted Lucene index:

              ```
              {
                "name": "The Empire Strikes Back",
                "characters.first": ["Luke", "Han"],
                "characters.last": ["Skywalker", "Solo"]
              }
              ```

              This is highly efficient, but there is no way to search on multiple fields of a character and be sure that the matching values came from the same character.
              ElasticGraph models this in the filtering API it offers for this case:

              ```
              query {
                films(filter: {
                  characters: {
                    first: {#{schema_def_state.schema_elements.any_satisfy}: {#{schema_def_state.schema_elements.equal_to_any_of}: ["Luke"]}}
                    last: {#{schema_def_state.schema_elements.any_satisfy}: {#{schema_def_state.schema_elements.equal_to_any_of}: ["Skywalker"]}}
                  }
                }) {
                  # ...
                }
              }
              ```

              As suggested by this filtering API, this will match any film that has a character with a first name of "Luke" and a character
              with the last name of "Skywalker", but this could be satisfied by two separate characters.

              2) `f.mapping type: "nested"` will cause each _object_ in the list to be indexed as a separate hidden document, preserving the independence of each.

              Given a `Film` document like "The Empire Strikes Back" from above, the `nested` type will index separate hidden documents for each character. This
              allows ElasticGraph to offer this filtering API instead:

              ```
              query {
                films(filter: {
                  characters: {#{schema_def_state.schema_elements.any_satisfy}: {
                    first: {#{schema_def_state.schema_elements.equal_to_any_of}: ["Luke"]}
                    last: {#{schema_def_state.schema_elements.equal_to_any_of}: ["Skywalker"]}
                  }}
                }) {
                  # ...
                }
              }
              ```

              As suggested by this filtering API, this will only match films that have a character named "Luke Skywalker". However, the Elasticsearch docs[^1][^2] warn
              that the `nested` mapping type can lead to performance problems, and index sorting cannot be configured[^3] when the `nested` type is used.

              [^1]: https://www.elastic.co/guide/en/elasticsearch/reference/8.10/nested.html
              [^2]: https://www.elastic.co/guide/en/elasticsearch/reference/8.10/joining-queries.html
              [^3]: https://www.elastic.co/guide/en/elasticsearch/reference/8.10/index-modules-index-sorting.html
            EOS
          end
        end
      end
    end
  end
end
