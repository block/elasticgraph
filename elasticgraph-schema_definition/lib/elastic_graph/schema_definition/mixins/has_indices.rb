# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/schema_definition/indexing/update_target_factory"

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Provides APIs for defining datastore indices.
      module HasIndices
        # @dynamic runtime_metadata_overrides
        # @private
        attr_reader :runtime_metadata_overrides

        # @return [::Symbol, nil] the default GraphQL resolver to use for fields on this type
        attr_reader :default_graphql_resolver
        # @dynamic default_graphql_resolver

        # @private
        def initialize(*args, **options)
          super(*args, **options)
          @runtime_metadata_overrides = {}
          resolve_fields_with :get_record_field_value
          yield self

          # Freeze `indices` so that the indexable status of a type does not change after instantiation.
          # (That would cause problems.)
          indices.freeze
        end

        # Converts the current type from being an _embedded_ type (that is, a type that is embedded within another indexed type) to an
        # _indexed_ type that resides in the named index definition. Indexed types are directly indexed into the datastore, and will be
        # queryable from the root `Query` type.
        #
        # @note Use {#root_query_fields} on indexed types to name the field that will be exposed on `Query`.
        # @note Indexed types must also define an `id` field, which ElasticGraph will use as the primary key.
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
        # @example Define a `campaigns` index
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
        def index(name, **settings, &block)
          indices.replace([Indexing::Index.new(name, settings, schema_def_state, self, &block)])
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

        # List of indices. (Currently we only store one but we may support multiple in the future).
        #
        # @private
        def indices
          @indices ||= []
        end

        # @return [Boolean] true if this type has an index
        def indexed?
          indices.any?
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
            index_definition_names: indices.map(&:name),
            graphql_fields_by_name: runtime_metadata_graphql_fields_by_name,
            elasticgraph_category: nil,
            source_type: nil,
            graphql_only_return_type: graphql_only?
          ).with(**runtime_metadata_overrides)
        end

        # Determines what the root `Query` fields will be to query this indexed type. In addition, this method accepts a block, which you
        # can use to customize the root query field (such as adding a GraphQL directive to it).
        #
        # @param plural [String] the plural name of the entity; used for the root `Query` field that queries documents of this indexed type
        # @param singular [String, nil] the singular name of the entity; used for the root `Query` field (with an `Aggregations` suffix) that
        #   queries aggregations of this indexed type. If not provided, will derive it from the type name (e.g. converting it to `camelCase`
        #   or `snake_case`, depending on configuration).
        # @yield [SchemaElements::Field] field on the root `Query` type used to query this indexed type, to support customization
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
        def root_query_fields(plural:, singular: nil, &customization_block)
          @plural_root_query_field_name = plural
          @singular_root_query_field_name = singular
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

        # @private
        def fields_with_sources
          indexing_fields_by_name_in_index.values.reject { |f| f.source.nil? }
        end

        private

        def self_update_target
          return nil if abstract? || !indexed?

          # We exclude `id` from `data_params` because `Indexer::Operator::Update` automatically includes
          # `params.id` so we don't want it duplicated at `params.data.id` alongside other data params.
          #
          # In addition, we exclude fields that have an alternate `source` -- those fields will get populated
          # by a different event and we don't want to risk "stomping" their value via this update target.
          data_params = indexing_fields_by_name_in_index.select { |name, field| name != "id" && field.source.nil? }.to_h do |field|
            [field, SchemaArtifacts::RuntimeMetadata::DynamicParam.new(source_path: field, cardinality: :one)]
          end

          index_runtime_metadata = indices.first.runtime_metadata

          Indexing::UpdateTargetFactory.new_normal_indexing_update_target(
            type: name,
            relationship: SELF_RELATIONSHIP_NAME,
            id_source: "id",
            data_params: data_params,
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
              if default_graphql_resolver
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
