# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/schema_elements/argument"
require "elastic_graph/schema_definition/schema_elements/built_in_types"
require "elastic_graph/schema_definition/schema_elements/deprecated_element"
require "elastic_graph/schema_definition/schema_elements/directive"
require "elastic_graph/schema_definition/schema_elements/enum_type"
require "elastic_graph/schema_definition/schema_elements/enum_value"
require "elastic_graph/schema_definition/schema_elements/enums_for_indexed_types"
require "elastic_graph/schema_definition/schema_elements/field"
require "elastic_graph/schema_definition/schema_elements/field_source"
require "elastic_graph/schema_definition/schema_elements/graphql_sdl_enumerator"
require "elastic_graph/schema_definition/schema_elements/input_field"
require "elastic_graph/schema_definition/schema_elements/input_type"
require "elastic_graph/schema_definition/schema_elements/interface_type"
require "elastic_graph/schema_definition/schema_elements/object_type"
require "elastic_graph/schema_definition/schema_elements/relationship"
require "elastic_graph/schema_definition/schema_elements/scalar_type"
require "elastic_graph/schema_definition/schema_elements/sort_order_enum_value"
require "elastic_graph/schema_definition/schema_elements/type_reference"
require "elastic_graph/schema_definition/schema_elements/type_with_subfields"
require "elastic_graph/schema_definition/schema_elements/union_type"

module ElasticGraph
  module SchemaDefinition
    # A class responsible for instantiating all schema elements. We want all schema element instantiation
    # to go through this one class to support extension libraries. ElasticGraph supports extension libraries
    # that provide modules that get extended onto specific instances of ElasticGraph framework classes. We
    # prefer this approach rather than having extension library modules applied via `include` or `prepend`,
    # because they _permanently modify_ the host classes. ElasticGraph is designed to avoid all mutable
    # global state, and that includes mutations to ElasticGraph class ancestor chains from extension libraries.
    #
    # Concretely, if we included or prepended extension libraries modules, we'd have a hard time keeping our
    # tests order-independent and deterministic while running all the ElasticGraph test suites in the same
    # Ruby process. A test using an extension library could cause a core ElasticGraph class to get mutated
    # in a way that impacts a test that runs in the same process later.  Instead, we expect extension libraries
    # to hook into ElasticGraph using `extend` on particular object instances.
    #
    # But that creates a bit of a problem: how can an extension library extend a module onto every instance
    # of a specific type of schema element while it is in use? The answer is this factory class:
    #
    #   - An extension library can extend a module onto `schema.factory`.
    #   - That module can in turn override any of these factory methods and extend another module onto the schema
    #     element instances.
    #
    # @private
    class Factory
      include Mixins::HasReadableToSAndInspect.new

      def initialize(state)
        @state = state
      end

      # Helper method to help enforce our desired invariant: we want _every_ instantiation of these schema
      # element classes to happen via this factory method provided here. To enforce that, this helper returns
      # the `new` method (as a `Method` object) after removing it from the given class. That makes it impossible
      # for `new` to be called by anyone except from the factory using the captured method object.
      def self.prevent_non_factory_instantiation_of(klass)
        klass.method(:new).tap do
          klass.singleton_class.undef_method :new
        end
      end

      def new_deprecated_element(name, defined_at:, defined_via:)
        @@deprecated_element_new.call(schema_def_state: @state, name: name, defined_at: defined_at, defined_via: defined_via)
      end
      @@deprecated_element_new = prevent_non_factory_instantiation_of(SchemaElements::DeprecatedElement)

      def new_argument(field, name, value_type)
        @@argument_new.call(@state, field, name, value_type).tap do |argument|
          yield argument if block_given?
        end
      end
      @@argument_new = prevent_non_factory_instantiation_of(SchemaElements::Argument)

      def new_built_in_types(api)
        @@built_in_types_new.call(api, @state)
      end
      @@built_in_types_new = prevent_non_factory_instantiation_of(SchemaElements::BuiltInTypes)

      def new_directive(name, arguments)
        @@directive_new.call(name, arguments)
      end
      @@directive_new = prevent_non_factory_instantiation_of(SchemaElements::Directive)

      def new_enum_type(name, &block)
        @@enum_type_new.call(@state, name, &(_ = block))
      end
      @@enum_type_new = prevent_non_factory_instantiation_of(SchemaElements::EnumType)

      def new_enum_value(name, original_name)
        @@enum_value_new.call(@state, name, original_name) do |enum_value|
          yield enum_value if block_given?
        end
      end
      @@enum_value_new = prevent_non_factory_instantiation_of(SchemaElements::EnumValue)

      def new_enums_for_indexed_types
        @@enums_for_indexed_types_new.call(@state)
      end
      @@enums_for_indexed_types_new = prevent_non_factory_instantiation_of(SchemaElements::EnumsForIndexedTypes)

      # Hard to type check this.
      # @dynamic new_field
      __skip__ = def new_field(**kwargs, &block)
                   @@field_new.call(schema_def_state: @state, **kwargs, &block)
                 end
      @@field_new = prevent_non_factory_instantiation_of(SchemaElements::Field)

      def new_graphql_sdl_enumerator(all_types)
        @@graphql_sdl_enumerator_new.call(@state, all_types)
      end
      @@graphql_sdl_enumerator_new = prevent_non_factory_instantiation_of(SchemaElements::GraphQLSDLEnumerator)

      # Hard to type check this.
      # @dynamic new_input_field
      __skip__ = def new_input_field(**kwargs)
                   input_field = @@input_field_new.call(new_field(as_input: true, **kwargs))
                   yield input_field
                   input_field
                 end
      @@input_field_new = prevent_non_factory_instantiation_of(SchemaElements::InputField)

      def new_input_type(name)
        @@input_type_new.call(@state, name) do |input_type|
          yield input_type
        end
      end
      @@input_type_new = prevent_non_factory_instantiation_of(SchemaElements::InputType)

      def new_filter_input_type(source_type, name_prefix: source_type, category: :filter_input)
        new_input_type(@state.type_ref(name_prefix).as_static_derived_type(category).name) do |t|
          t.documentation <<~EOS
            Input type used to specify filters on `#{source_type}` fields.

            Will match all documents if passed as an empty object (or as `null`).
          EOS

          t.field @state.schema_elements.any_of, "[#{t.name}!]" do |f|
            f.documentation <<~EOS
              Matches records where any of the provided sub-filters evaluate to true.
              This works just like an OR operator in SQL.

              When `null` is passed, matches all documents.
              When an empty list is passed, this part of the filter matches no documents.
            EOS
          end

          t.field @state.schema_elements.not, t.name do |f|
            f.documentation <<~EOS
              Matches records where the provided sub-filter evaluates to false.
              This works just like a NOT operator in SQL.

              When `null` or an empty object is passed, matches no documents.
            EOS
          end

          yield t
        end
      end

      # Builds the standard set of filter input types for types which are indexing leaf types.
      #
      # All GraphQL leaf types (enums and scalars) are indexing leaf types, but some GraphQL object types are
      # as well. For example, `GeoLocation` is an object type in GraphQL (with separate lat/long fields) but is
      # an indexing leaf type because we use the datastore `geo_point` type for it.
      def build_standard_filter_input_types_for_index_leaf_type(source_type, name_prefix: source_type, &define_filter_fields)
        single_value_filter = new_filter_input_type(source_type, name_prefix: name_prefix, &define_filter_fields)
        list_filter = new_list_filter_input_type(source_type, name_prefix: name_prefix, any_satisfy_type_category: :list_element_filter_input)
        list_element_filter = new_list_element_filter_input_type(source_type, name_prefix: name_prefix, &define_filter_fields)

        [single_value_filter, list_filter, list_element_filter]
      end

      # Builds the standard set of filter input types for types which are indexing object types.
      #
      # Most GraphQL object types are indexing object types as well, but not all.
      # For example, `GeoLocation` is an object type in GraphQL (with separate lat/long fields) but is
      # an indexing leaf type because we use the datastore `geo_point` type for it.
      def build_standard_filter_input_types_for_index_object_type(source_type, name_prefix: source_type, &define_filter_fields)
        single_value_filter = new_filter_input_type(source_type, name_prefix: name_prefix, &define_filter_fields)
        list_filter = new_list_filter_input_type(source_type, name_prefix: name_prefix, any_satisfy_type_category: :filter_input)
        fields_list_filter = new_fields_list_filter_input_type(source_type, name_prefix: name_prefix)

        [single_value_filter, list_filter, fields_list_filter]
      end

      def build_relay_pagination_types(type_name, include_total_edge_count: false, derived_indexed_types: [], support_pagination: true, &customize_connection)
        [
          (edge_type_for(type_name) if support_pagination),
          connection_type_for(type_name, include_total_edge_count, derived_indexed_types, support_pagination, &customize_connection)
        ].compact
      end

      def new_interface_type(name)
        @@interface_type_new.call(@state, name.to_s) do |interface_type|
          yield interface_type
        end
      end
      @@interface_type_new = prevent_non_factory_instantiation_of(SchemaElements::InterfaceType)

      def new_object_type(name)
        @@object_type_new.call(@state, name.to_s) do |object_type|
          yield object_type if block_given?
        end
      end
      @@object_type_new = prevent_non_factory_instantiation_of(SchemaElements::ObjectType)

      def new_scalar_type(name)
        @@scalar_type_new.call(@state, name.to_s) do |scalar_type|
          yield scalar_type
        end
      end
      @@scalar_type_new = prevent_non_factory_instantiation_of(SchemaElements::ScalarType)

      def new_sort_order_enum_value(enum_value, sort_order_field_path)
        @@sort_order_enum_value_new.call(enum_value, sort_order_field_path)
      end
      @@sort_order_enum_value_new = prevent_non_factory_instantiation_of(SchemaElements::SortOrderEnumValue)

      def new_type_reference(name)
        @@type_reference_new.call(name, @state)
      end
      @@type_reference_new = prevent_non_factory_instantiation_of(SchemaElements::TypeReference)

      def new_type_with_subfields(schema_kind, name, wrapping_type:, field_factory:)
        @@type_with_subfields_new.call(schema_kind, @state, name, wrapping_type: wrapping_type, field_factory: field_factory) do |type_with_subfields|
          yield type_with_subfields
        end
      end
      @@type_with_subfields_new = prevent_non_factory_instantiation_of(SchemaElements::TypeWithSubfields)

      def new_union_type(name)
        @@union_type_new.call(@state, name.to_s) do |union_type|
          yield union_type
        end
      end
      @@union_type_new = prevent_non_factory_instantiation_of(SchemaElements::UnionType)

      def new_field_source(relationship_name:, field_path:)
        @@field_source_new.call(relationship_name, field_path)
      end
      @@field_source_new = prevent_non_factory_instantiation_of(SchemaElements::FieldSource)

      def new_relationship(field, cardinality:, related_type:, foreign_key:, direction:)
        @@relationship_new.call(
          field,
          cardinality: cardinality,
          related_type: related_type,
          foreign_key: foreign_key,
          direction: direction
        )
      end
      @@relationship_new = prevent_non_factory_instantiation_of(SchemaElements::Relationship)

      # Responsible for creating a new `*AggregatedValues` type for an index leaf type.
      #
      # An index leaf type is a scalar, enum, object type that is backed by a single, indivisible
      # field in the index. All scalar and enum types are index leaf types, and object types
      # rarely (but sometimes) are. For example, the `GeoLocation` object type has two subfields
      # (`latitude` and `longitude`) but is backed by a single `geo_point` field in the index,
      # so it is an index leaf type.
      def new_aggregated_values_type_for_index_leaf_type(index_leaf_type)
        new_object_type @state.type_ref(index_leaf_type).as_aggregated_values.name do |type|
          type.graphql_only true
          type.documentation "A return type used from aggregations to provided aggregated values over `#{index_leaf_type}` fields."
          type.default_graphql_resolver = :object
          type.override_runtime_metadata(elasticgraph_category: :scalar_aggregated_values)

          type.field @state.schema_elements.approximate_distinct_value_count, "JsonSafeLong", graphql_only: true do |f|
            # Note: the 1-6% accuracy figure comes from the Elasticsearch docs:
            # https://www.elastic.co/guide/en/elasticsearch/reference/8.10/search-aggregations-metrics-cardinality-aggregation.html#_counts_are_approximate
            f.documentation <<~EOS
              An approximation of the number of unique values for this field within this grouping.

              The approximation uses the HyperLogLog++ algorithm from the [HyperLogLog in Practice](https://research.google.com/pubs/archive/40671.pdf)
              paper. The accuracy of the returned value varies based on the specific dataset, but
              it usually differs from the true distinct value count by less than 7%.
            EOS

            f.runtime_metadata_computation_detail empty_bucket_value: 0, function: :cardinality
          end

          yield type
        end
      end

      private

      def new_list_filter_input_type(source_type, name_prefix:, any_satisfy_type_category:)
        any_satisfy = @state.schema_elements.any_satisfy
        all_of = @state.schema_elements.all_of

        new_filter_input_type "[#{source_type}]", name_prefix: name_prefix, category: :list_filter_input do |t|
          t.field any_satisfy, @state.type_ref(name_prefix).as_static_derived_type(any_satisfy_type_category).name do |f|
            f.documentation <<~EOS
              Matches records where any of the list elements match the provided sub-filter.

              When `null` or an empty object is passed, matches all documents.
            EOS
          end

          t.field all_of, "[#{t.name}!]" do |f|
            f.documentation <<~EOS
              Matches records where all of the provided sub-filters evaluate to true. This works just like an AND operator in SQL.

              Note: multiple filters are automatically ANDed together. This is only needed when you have multiple filters that can't
              be provided on a single `#{t.name}` input because of collisions between key names. For example, if you want to provide
              multiple `#{any_satisfy}: ...` filters, you could do `#{all_of}: [{#{any_satisfy}: ...}, {#{any_satisfy}: ...}]`.

              When `null` or an empty list is passed, matches all documents.
            EOS
          end

          define_list_counts_filter_field_on(t)
        end
      end

      # Generates a filter type used on elements of a list. Referenced from a `#{type}ListFilterInput` input
      # (which is referenced from `any_satisfy`).
      def new_list_element_filter_input_type(source_type, name_prefix:)
        new_filter_input_type source_type, name_prefix: name_prefix, category: :list_element_filter_input do |t|
          t.documentation <<~EOS
            Input type used to specify filters on elements of a `[#{source_type}]` field.

            Will match all documents if passed as an empty object (or as `null`).
          EOS

          # While we support `not: {any_satisfy: ...}` we do not support `any_satisfy: {not ...}` at this time.
          # Since `any_satisfy` does not have a node in the datastore query expression, the naive way we'd
          # generate the datastore filter would be the same for both cases. However, they should have different
          # semantics.
          #
          # For example, if we have these documents:
          #
          # - d1: {tags: ["a", "b"]}
          # - d2: {tags: ["b", "c"]}
          # - d3: {tags: []}
          # - d4: {tags: ["a"]}
          #
          # Then `not: {any_satisfy: {equal_to_any_of: ["a"]}}` should (and does) match d2 and d3.
          # But `any_satisfy: {not: {equal_to_any_of: ["a"]}}` should match d1 and d2 (both have a tag that is not equal to "a").
          # However, Elasticsearch and OpenSearch do not allow us to express that.
          #
          # Technically, we could probably get it to work if we implemented negations of all our filter operators.
          # For example, `gt` negated is `lte`, `lt` negated is `gte`, etc. But for some operators that's not easy.
          # There is no available negation of `equal_to_any_of`, but we could maybe get it to work by using a regex
          # operator that matches any term EXCEPT the provided value, but that's non-trivial to implement and could
          # be quite expensive. So for now we just don't support this.
          #
          # ...therefore, we need to omit `not` from the generated filter here.
          t.graphql_fields_by_name.delete(@state.schema_elements.not)

          yield t
        end
      end

      # Generates a filter type used for objects within a list (either at a parent or some ancestor level)
      # when the `nested ` type is not used. The datastore indexes each leaf field as its own flattened list
      # of values. We mirror that structure with this filter type, only offering `any_satisfy` on leaf fields.
      def new_fields_list_filter_input_type(source_type_name, name_prefix:)
        source_type = @state.object_types_by_name.fetch(source_type_name)

        new_filter_input_type source_type_name, name_prefix: name_prefix, category: :fields_list_filter_input do |t|
          t.documentation <<~EOS
            Input type used to specify filters on a `#{source_type_name}` object referenced directly
            or transitively from a list field that has been configured to index each leaf field as
            its own flattened list of values.

            Will match all documents if passed as an empty object (or as `null`).
          EOS

          source_type.graphql_fields_by_name.each do |field_name, field|
            next unless field.filterable?
            t.graphql_fields_by_name[field_name] = field.to_filter_field(
              parent_type: t,
              # We are never filtering on single values in this context (since we are already
              # within a list that isn't using the `nested` mapping type).
              for_single_value: false
            )
          end

          # We want to add a `count` field so that clients can filter on the count of elements of this list field.
          # However, if the object type of this field has a user-defined `count` field then we cannot do that, as that
          # would create a conflict. So we omit it in that case. Users will still be able to filter on the count of
          # the leaf fields if they spell out the full filter path to a leaf field.
          count_field_name = @state.schema_elements.count
          if t.graphql_fields_by_name.key?(count_field_name)
            @state.output.puts <<~EOS
              WARNING: Since a `#{source_type_name}.#{count_field_name}` field exists, ElasticGraph is not able to
              define its typical `#{t.name}.#{count_field_name}` field, which allows clients to filter on the count
              of values for a `[#{source_type.name}]` field. Clients will still be able to filter on the `#{count_field_name}`
              at a leaf field path. However, there are a couple ways this naming conflict can be avoided if desired:

              1. Pick a different name for the `#{source_type_name}.#{count_field_name}` field.
              2. Change the name used by ElasticGraph for this field. To do that, pass a
                 `schema_element_name_overrides: {#{count_field_name.inspect} => "alt_name"}` option alongside
                 `schema_element_name_form: ...` when defining `ElasticGraph::SchemaDefinition::RakeTasks`
                 (typically in the `Rakefile`).
            EOS
          else
            define_list_counts_filter_field_on(t)
          end
        end
      end

      def define_list_counts_filter_field_on(type)
        # Note: we use `IntFilterInput` (instead of `JsonSafeLongFilterInput` or similar...) to align with the
        # `integer` mapping type we use for the `__counts` field. If we ever change that
        # in `list_counts_mapping.rb`, we'll want to consider changing this as well.
        #
        # We use `name_in_index: __counts` because we need to indicate that it's the list `count` operator
        # rather than a schema field named "counts". Our filter interpreter logic relies on that name.
        # We can count on `__counts` not being used by a real schema field because the GraphQL spec reserves
        # the `__` prefix for its own use.
        type.field @state.schema_elements.count, @state.type_ref("Int").as_filter_input.name, name_in_index: LIST_COUNTS_FIELD do |f|
          f.documentation <<~EOS
            Used to filter on the number of non-null elements in this list field.

            When `null` or an empty object is passed, matches all documents.
          EOS
        end
      end

      def edge_type_for(type_name)
        type_ref = @state.type_ref(type_name)
        new_object_type type_ref.as_edge.name do |t|
          t.relay_pagination_type = true
          t.default_graphql_resolver = :object
          t.override_runtime_metadata(elasticgraph_category: :relay_edge)

          t.documentation <<~EOS
            Represents a specific `#{type_name}` in the context of a `#{type_ref.as_connection.name}`,
            providing access to both the `#{type_name}` and a pagination `Cursor`.

            See the [Relay GraphQL Cursor Connections
            Specification](https://relay.dev/graphql/connections.htm#sec-Edge-Types) for more info.
          EOS

          t.field @state.schema_elements.node, type_name do |f|
            f.documentation "The `#{type_name}` of this edge."
          end

          t.field @state.schema_elements.cursor, "Cursor" do |f|
            f.documentation <<~EOS
              The `Cursor` of this `#{type_name}`. This can be passed in the next query as
              a `before` or `after` argument to continue paginating from this `#{type_name}`.
            EOS
          end
        end
      end

      def connection_type_for(type_name, include_total_edge_count, derived_indexed_types, support_pagination)
        type_ref = @state.type_ref(type_name)
        new_object_type type_ref.as_connection.name do |t|
          t.relay_pagination_type = true
          t.default_graphql_resolver = :object
          t.override_runtime_metadata(elasticgraph_category: :relay_connection)

          if support_pagination
            t.documentation <<~EOS
              Represents a paginated collection of `#{type_name}` results.

              See the [Relay GraphQL Cursor Connections
              Specification](https://relay.dev/graphql/connections.htm#sec-Connection-Types) for more info.
            EOS
          else
            t.documentation "Represents a collection of `#{type_name}` results."
          end

          if support_pagination
            t.field @state.schema_elements.edges, "[#{type_ref.as_edge.name}!]!" do |f|
              f.documentation "Wraps a specific `#{type_name}` to pair it with its pagination cursor."
            end
          end

          t.field @state.schema_elements.nodes, "[#{type_name}!]!" do |f|
            f.documentation "The list of `#{type_name}` results."
          end

          if support_pagination
            t.field @state.schema_elements.page_info, "PageInfo!" do |f|
              f.documentation "Provides pagination-related information."
            end
          end

          if include_total_edge_count
            t.field @state.schema_elements.total_edge_count, "JsonSafeLong!" do |f|
              f.documentation "The total number of edges available in this connection to paginate over."
            end
          end

          yield t if block_given?
        end
      end
    end
  end
end
