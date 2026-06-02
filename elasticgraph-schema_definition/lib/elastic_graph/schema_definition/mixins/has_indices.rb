# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/configured_graphql_resolver"
require "elastic_graph/schema_definition/indexing/update_target_factory"

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Provides APIs for defining datastore indices.
      module HasIndices
        # Resolver auto-wired on any no-argument field that returns a namespace type. A namespace type
        # carries no data of its own; this resolver just provides a non-null passthrough object for the
        # GraphQL machinery so each child field's own resolver can run.
        NAMESPACE_RESOLVER = SchemaArtifacts::RuntimeMetadata::ConfiguredGraphQLResolver.new(:namespace_ref, {})

        # @dynamic runtime_metadata_overrides
        # @private
        attr_reader :runtime_metadata_overrides

        # @return [::Symbol, nil] the default GraphQL resolver to use for fields on this type
        attr_reader :default_graphql_resolver
        # @dynamic default_graphql_resolver

        # @private
        def initialize(*args, **options)
          super(*args, **options)
          initialize_has_indices { yield self }
        end

        # Declares a datastore index for the current type, converting it from an _embedded_ type to an _indexed_ type
        # that is directly queryable from the root `Query` type. When called on an abstract `interface_type` or
        # `union_type`, concrete subtypes inherit the index by default — they share the same datastore index without
        # needing to call `t.index` themselves. A subtype can opt out of this shared index inheritance by calling
        # `t.index` with a different name to use a dedicated index instead.
        #
        # @note Use {#root_query_fields} on indexed types to name the field that will be exposed on `Query`.
        # @note Indexed types must also define an `id` field, which ElasticGraph will use as the primary key.
        #   When an abstract type declares the index, each concrete subtype must also define `id`.
        # @note Datastore index settings can also be defined (or overridden) in an environment-specific settings YAML file. Index settings
        #   that you want to configure differently for different environments (such as `index.number_of_shards`—-production and staging
        #   will probably need different numbers!) should be configured in the per-environment YAML configuration files rather than here.
        #
        # @param name [String] name of the index. See the [Elasticsearch docs](https://www.elastic.co/guide/en/elasticsearch/reference/8.15/indices-create-index.html#indices-create-api-path-params)
        #   for restrictions.
        # @param settings [Hash<Symbol, Object>] datastore index settings you want applied to every environment. See the [Elasticsearch docs](https://www.elastic.co/guide/en/elasticsearch/reference/8.15/index-modules.html#index-modules-settings)
        #   for a list of valid settings, but be sure to omit the `index.` prefix here.
        # @yield [Indexing::Index] the index, so it can be customized further
        # @return [void]
        #
        # @example Define a `campaigns` index on a concrete type
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #
        #       t.index(
        #         "campaigns",
        #         # Configure `index.refresh_interval`.
        #         refresh_interval: "1s",
        #         # Use `index.search` to log warnings for any search query that take more than five seconds.
        #         search: {slowlog: {level: "WARN", threshold: {query: {warn: "5s"}}}}
        #       ) do |i|
        #         # The index can be customized further here.
        #       end
        #     end
        #   end
        #
        # @example Declare a shared index on an interface
        #   ElasticGraph.define_schema do |schema|
        #     schema.interface_type "Vehicle" do |t|
        #       t.field "id", "ID"
        #       t.field "make", "String"
        #       t.index "vehicles"
        #     end
        #
        #     schema.object_type "Car" do |t|
        #       t.implements "Vehicle"
        #       t.field "id", "ID"
        #       t.field "make", "String"
        #       t.field "numDoors", "Int"
        #       # Inherits the `vehicles` index — no need to call `t.index`.
        #     end
        #
        #     schema.object_type "Motorcycle" do |t|
        #       t.implements "Vehicle"
        #       t.field "id", "ID"
        #       t.field "make", "String"
        #       t.field "engineCC", "Int"
        #       # Opts out of the shared index and gets its own dedicated index instead.
        #       t.index "motorcycles"
        #     end
        #   end
        def index(name, **settings, &block)
          unless @can_configure_index
            raise Errors::SchemaError, "Cannot define an index on `#{self.name}` after initialization is complete. " \
              "Indices must be configured during initial type definition."
          end

          if @own_index_def
            raise Errors::SchemaError, "Cannot define multiple indices on `#{self.name}`. " \
              "Only one index per type is supported. An index named `#{@own_index_def.name}` has already been defined."
          end

          schema_def_state.register_index(name, self)
          @own_index_def = schema_def_state.factory.new_index(name, settings, self, &block)
        end

        # Configures the default GraphQL resolver that will be used to resolve the fields of this type. Individual fields
        # can override this using {SchemaElements::Field#resolve_with}.
        #
        # @param default_resolver_name [Symbol] name of the GraphQL resolver to use as the default for fields of this type
        # @param config [Hash<Symbol, Object>] configuration parameters for the resolver
        # @return [void]
        # @see API#register_graphql_resolver
        def resolve_fields_with(default_resolver_name, **config)
          @default_graphql_resolver = default_resolver_name&.then do
            SchemaArtifacts::RuntimeMetadata::ConfiguredGraphQLResolver.new(it, config)
          end
        end

        # @return [Indexing::Index, nil] the index definition directly defined on this type, or nil if no index is defined directly.
        #   This will be nil when a type is inheriting an index definition from an abstract parent type.
        def own_index_def
          @own_index_def
        end

        # @return [Boolean] true if this type has its own index definition (not inherited from an abstract parent)
        def has_own_index_def?
          !@own_index_def.nil?
        end

        # Resolves this type's index definition. This will be one of:
        # - This type's own_index_def (if it directly defines an index)
        # - An inherited index from an abstract supertype (union/interface) that has an index
        #
        # This type can be a subtype of multiple abstract types (e.g., implements multiple interfaces), but unless it
        # defines its own index, at most one of its supertypes may have an index. If multiple parent types are indexed,
        # this method raises an error to prevent ambiguity about which index to inherit.
        #
        # @return [Indexing::Index, nil] the index definition, or nil if this type has no index
        # @raise [Errors::SchemaError] if this type is a subtype of multiple indexed abstract types
        def index_def
          return own_index_def if has_own_index_def?

          indexed_supertypes = recursively_resolve_supertypes.select(&:has_own_index_def?)

          if indexed_supertypes.size > 1
            parent_names = indexed_supertypes.map { |p| p.own_index_def.name }.join(", ")
            raise Errors::SchemaError,
              "The `#{name}` type is a subtype of multiple indexed abstract types (#{parent_names}). " \
              "If a concrete type does not define an index, it may not be a member of multiple indexed abstract types."
          end

          indexed_supertypes.first&.own_index_def
        end

        # @return [Boolean] true if this type is a root document type that lives at a document root in the datastore (is indexed).
        #   This returns true for types with their own index definition or types that inherit an index from a supertype.
        def root_document_type?
          !index_def.nil?
        end

        # @return [Boolean] true if this type is directly queryable via a type-specific field on the root `Query` type.
        # @note A concrete subtype that inherits an index from an abstract parent is NOT directly queryable on its own —
        #   only the abstract type that declared the index is. Use {#root_document_type?} to check whether a type
        #   is stored at the root of any index (own or inherited).
        def directly_queryable?
          has_own_index_def?
        end

        # Abstract types are rare, so return false. This can be overridden in the host class.
        #
        # @private
        def abstract?
          false
        end

        # Configures the ElasticGraph indexer to derive another type from this indexed type, using the `from_id` field as
        # the source of the `id` of the derived type, and the provided block for the definitions of the derived fields.
        #
        # @param name [String] name of the derived type
        # @param from_id [String] path to the source type field with `id` values for the derived type
        # @param route_with [String, nil] path to the source type field with values for shard routing on the derived type
        # @param rollover_with [String, nil] path to the source type field with values for index rollover on the derived type
        # @yield [Indexing::DerivedIndexedType] configuration object for field derivations
        # @return [void]
        #
        # @example Derive a `Course` type from `StudentCourseEnrollment` events
        #   ElasticGraph.define_schema do |schema|
        #     # `StudentCourseEnrollment` is a directly indexed type.
        #     schema.object_type "StudentCourseEnrollment" do |t|
        #       t.field "id", "ID"
        #       t.field "courseId", "ID"
        #       t.field "courseName", "String"
        #       t.field "studentName", "String"
        #       t.field "courseStartDate", "Date"
        #
        #       t.index "student_course_enrollments"
        #
        #       # Here we define how the `Course` indexed type  is derived when we index `StudentCourseEnrollment` events.
        #       t.derive_indexed_type_fields "Course", from_id: "courseId" do |derive|
        #         # `derive` is an instance of `DerivedIndexedType`.
        #         derive.immutable_value "name", from: "courseName"
        #         derive.append_only_set "students", from: "studentName"
        #         derive.min_value "firstOfferedDate", from: "courseStartDate"
        #         derive.max_value "mostRecentlyOfferedDate", from: "courseStartDate"
        #       end
        #     end
        #
        #     # `Course` is an indexed type that is derived entirely from `StudentCourseEnrollment` events.
        #     schema.object_type "Course" do |t|
        #       t.field "id", "ID"
        #       t.field "name", "String"
        #       t.field "students", "[String!]!"
        #       t.field "firstOfferedDate", "Date"
        #       t.field "mostRecentlyOfferedDate", "Date"
        #
        #       t.index "courses"
        #     end
        #   end
        def derive_indexed_type_fields(
          name,
          from_id:,
          route_with: nil,
          rollover_with: nil,
          &block
        )
          Indexing::DerivedIndexedType.new(
            source_type: self,
            destination_type_ref: schema_def_state.type_ref(name).to_final_form,
            id_source: from_id,
            routing_value_source: route_with,
            rollover_timestamp_value_source: rollover_with,
            &block
          ).tap { |dit| derived_indexed_types << dit }
        end

        # @return [Array<Indexing::DerivedIndexedType>] list of derived types for this source type
        def derived_indexed_types
          @derived_indexed_types ||= []
        end

        # Configures overrides for runtime metadata. The provided runtime metadata values will be persisted in the
        # `runtime_metadata.yaml` schema artifact and made available at runtime to `elasticgraph-graphql` and
        # `elasticgraph-indexer`.
        #
        # @return [void]
        def override_runtime_metadata(**overrides)
          @runtime_metadata_overrides.merge!(overrides)
        end

        # @private
        def runtime_metadata(extra_update_targets)
          SchemaArtifacts::RuntimeMetadata::ObjectType.new(
            update_targets: derived_indexed_types.map(&:runtime_metadata_for_source_type) + [self_update_target].compact + extra_update_targets,
            index_definition_names: [index_def&.name].compact,
            graphql_fields_by_name: runtime_metadata_graphql_fields_by_name,
            elasticgraph_category: nil,
            source_type: nil,
            graphql_only_return_type: graphql_only?
          ).with(**runtime_metadata_overrides)
        end

        # Determines what the root query fields will be to query this indexed type. In addition, this method accepts a block, which you
        # can use to customize the root query field (such as adding a GraphQL directive to it).
        #
        # @param plural [String] the plural name of the entity; used for the root query field that queries documents of this indexed type
        # @param singular [String, nil] the singular name of the entity; used for the root query field (with an `Aggregations` suffix) that
        #   queries aggregations of this indexed type. If not provided, will derive it from the type name (e.g. converting it to `camelCase`
        #   or `snake_case`, depending on configuration).
        # @param on [String] name of the object type on which the root fields should be defined. Defaults to `"Query"`. To route the
        #   fields to a {API#namespace_type namespace type} instead, pass its name (e.g. `"OlapQuery"`). The target type must have been
        #   declared via `namespace_type`; otherwise an error is raised at schema-definition time.
        # @yield [SchemaElements::Field] field on the target type used to query this indexed type, to support customization
        # @return [void]
        #
        # @example Set `plural` and `singular` names
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Person" do |t|
        #       t.field "id", "ID"
        #
        #       # Results in `Query.people` and `Query.personAggregations`.
        #       t.root_query_fields plural: "people", singular: "person"
        #
        #       t.index "people"
        #     end
        #   end
        #
        # @example Customize `Query` fields
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Person" do |t|
        #       t.field "id", "ID"
        #
        #       t.root_query_fields plural: "people", singular: "person" do |f|
        #         # Marks `Query.people` and `Query.personAggregations` as deprecated.
        #         f.directive "deprecated"
        #       end
        #
        #       t.index "people"
        #     end
        #   end
        #
        # @example Route root fields to a namespace type
        #   ElasticGraph.define_schema do |schema|
        #     schema.namespace_type "OlapQuery"
        #
        #     schema.on_root_query_type do |t|
        #       t.field "olap", "OlapQuery"
        #     end
        #
        #     schema.object_type "Widget" do |t|
        #       # Results in `OlapQuery.widgets` and `OlapQuery.widgetAggregations`.
        #       t.root_query_fields plural: "widgets", on: "OlapQuery"
        #       t.field "id", "ID"
        #       t.index "widgets"
        #     end
        #   end
        def root_query_fields(plural:, singular: nil, on: root_query_fields_target_namespace, &customization_block)
          @plural_root_query_field_name = plural
          @singular_root_query_field_name = singular
          @root_query_fields_target_namespace = on
          @root_query_fields_customizations = customization_block
        end

        # @return [String] the plural name of the entity; used for the root `Query` field that queries documents of this indexed type
        def plural_root_query_field_name
          @plural_root_query_field_name || naively_pluralize_type_name(name)
        end

        # @return [String] the singular name of the entity; used for the root `Query` field (with an `Aggregations` suffix) that queries
        #   aggregations of this indexed type. If not provided, will derive it from the type name (e.g. converting it to `camelCase` or
        #   `snake_case`, depending on configuration).
        def singular_root_query_field_name
          @singular_root_query_field_name || to_field_name(name)
        end

        # @private
        def root_query_fields_customizations
          @root_query_fields_customizations
        end

        # @return [String] name of the object type on which the root fields for this indexed type should be defined.
        #   Defaults to `"Query"`; can be overridden via the `on:` parameter of {#root_query_fields}.
        def root_query_fields_target_namespace
          @root_query_fields_target_namespace || "Query"
        end

        # Registers the root query fields for this indexed type on its target namespace type. Called during
        # schema finalization, after all user type definitions have been evaluated.
        #
        # @private
        def register_root_query_fields
          target_type = resolve_root_query_fields_target

          target_type.relates_to_many(
            plural_root_query_field_name,
            name,
            via: "ignore",
            dir: :in,
            singular: singular_root_query_field_name
          ) do |f|
            f.documentation "Fetches `#{name}`s based on the provided arguments."
            f.resolve_with :indexed_type_root_fields
            f.hide_relationship_runtime_metadata = true
            root_query_fields_customizations&.call(f)
          end

          # Add additional efficiency hints to the aggregation field documentation if we have any such hints.
          # This needs to be outside the `relates_to_many` block because `relates_to_many` adds its own "suffix" to
          # the field documentation, and here we add another one.
          if (agg_efficiency_hint = aggregation_efficiency_hint)
            agg_name = schema_def_state.schema_elements.normalize_case("#{singular_root_query_field_name}_aggregations")
            agg_field = target_type.graphql_fields_by_name.fetch(agg_name)
            agg_field.documentation "#{agg_field.doc_comment}\n\n#{agg_efficiency_hint}"
          end
        end

        # @private
        def fields_with_sources
          indexing_fields_by_name_in_index.values.reject { |f| f.source.nil? }
        end

        # Returns the list of `_source.excludes` paths for non-returnable, non-highlightable fields.
        #
        # Hidden highlightable fields must remain in `_source` so the datastore can still
        # produce search highlight snippets for them.
        #
        # Uses `indexing_fields_by_name_in_index` for traversal (same as
        # `index_field_runtime_metadata_tuples`) to avoid infinite recursion
        # through interface/union subtype cycles.
        #
        # @private
        def source_excludes_paths(path_prefix = "", under_non_returnable_parent = false)
          indexing_fields_by_name_in_index.flat_map do |name, field|
            path = path_prefix + name
            object_type = field.type.fully_unwrapped.as_object_type
            non_returnable = under_non_returnable_parent || !field.returnable?

            if object_type
              if non_returnable && !field.highlightable?
                ["#{path}.*"]
              else
                object_type.source_excludes_paths("#{path}.", non_returnable)
              end
            elsif non_returnable && !field.highlightable?
              [path]
            else
              []
            end
          end
        end

        private

        def initialize_has_indices
          @runtime_metadata_overrides = {}
          @can_configure_index = true
          resolve_fields_with :get_record_field_value
          yield
          @can_configure_index = false
        end

        def self_update_target
          return nil if abstract? || !root_document_type?

          # We exclude `id` from `top_level_fields_params` because `Indexer::Operator::Update` automatically includes
          # `params.id` so we don't want it duplicated at `params.topLevelFields.id` alongside other top-level fields params.
          #
          # In addition, we exclude fields that have an alternate `source` -- those fields will get populated
          # by a different event and we don't want to risk "stomping" their value via this update target.
          top_level_fields_params = indexing_fields_by_name_in_index.select { |name, field| name != "id" && field.source.nil? }.to_h do |field|
            [field, SchemaArtifacts::RuntimeMetadata::DynamicParam.new(source_path: field, cardinality: :one)]
          end

          index_runtime_metadata = index_def.runtime_metadata

          Indexing::UpdateTargetFactory.new_normal_indexing_update_target(
            type: name,
            relationship: SELF_RELATIONSHIP_NAME,
            id_source: "id",
            top_level_fields_params: top_level_fields_params,
            sourced_from_nested_params: SchemaArtifacts::RuntimeMetadata::SourcedFromNestedParams::EMPTY,
            # Some day we may want to consider supporting multiple indices. If/when we add support for that,
            # we'll need to change the runtime metadata here to have a map of these values, keyed by index
            # name.
            routing_value_source: index_runtime_metadata.route_with,
            rollover_timestamp_value_source: index_runtime_metadata.rollover&.timestamp_field_path
          )
        end

        def runtime_metadata_graphql_fields_by_name
          graphql_fields_by_name.transform_values do |field|
            field_metadata = field.runtime_metadata_graphql_field

            if field_metadata.resolver.nil?
              # A no-argument field whose return type is a namespace type is auto-wired to the shared
              # `NAMESPACE_RESOLVER`. Intermediate namespace wrappers (e.g. `Query.olap` returning
              # `OlapQuery!`) are pure groupings with no backing data; the resolver provides an inert
              # passthrough object that child resolvers hang off of. Fields that declare arguments are
              # excluded since arguments signal the author wants custom resolution.
              if field.args.empty? && field.type_is_namespace?
                field_metadata.with(resolver: NAMESPACE_RESOLVER)
              elsif default_graphql_resolver
                field_metadata.with(resolver: default_graphql_resolver)
              else
                parent_type_option =
                  if name == "Query"
                    # With `Query`, we don't want to use the `default_graphql_resolver`. Each field should set its own resolver.
                    ""
                  else
                    "the `default_graphql_resolver` on the parent type (`#{name}`) or "
                  end

                raise Errors::SchemaError, "`#{name}.#{field.name}` needs a resolver. Fix by assigning #{parent_type_option}" \
                  "a `resolver` on the field (`#{field.name}`)."
              end
            else
              field_metadata
            end
          end
        end

        def resolve_root_query_fields_target
          target_name = root_query_fields_target_namespace
          target_type = schema_def_state.object_types_by_name[target_name]

          if target_type.nil?
            raise Errors::SchemaError,
              "`#{name}` uses `root_query_fields on: #{target_name.inspect}`, but no type named `#{target_name}` is defined. " \
              "Declare it with `schema.namespace_type #{target_name.inspect}` or correct the `on:` value."
          end

          unless schema_def_state.namespace_types_by_name.key?(target_name)
            raise Errors::SchemaError,
              "`#{name}` uses `root_query_fields on: #{target_name.inspect}`, but `#{target_name}` is not a namespace type. " \
              "`on:` must reference a type declared with `schema.namespace_type`."
          end

          target_type
        end

        def aggregation_efficiency_hint
          return nil if derived_indexed_types.empty?

          hints = derived_indexed_types.map do |type|
            derived_indexing_type = schema_def_state.types_by_name.fetch(type.destination_type_ref.name)
            alternate_field_name = (_ = derived_indexing_type).plural_root_query_field_name
            grouping_field = type.id_source

            "  - The root `#{alternate_field_name}` field groups by `#{grouping_field}`"
          end

          <<~EOS
            Note: aggregation queries are relatively expensive, and some fields have been pre-aggregated to allow
            more efficient queries for some common aggregation cases:

            #{hints.join("\n")}
          EOS
        end

        # Provides a "best effort" conversion of a type name to the plural form.
        # In practice, schema definers should set `root_query_field` on their
        # indexed types so we don't have to try to convert the type to its plural
        # form. Still, this has value, particularly given our existing tests
        # (where I don't want to require that we set this).
        #
        # Note: we could pull in ActiveSupport to pluralize more accurately, but I
        # really don't want to pull in any part of Rails just for that :(.
        def naively_pluralize_type_name(type_name)
          normalized = to_field_name(type_name)
          normalized + (normalized.end_with?("s") ? "es" : "s")
        end

        def to_field_name(type_name)
          name_without_leading_uppercase = type_name.sub(/^([[:upper:]])/) { $1.downcase }
          schema_def_state.schema_elements.normalize_case(name_without_leading_uppercase)
        end
      end
    end
  end
end
