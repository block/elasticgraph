# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      module RuntimeMetadataSupport
        def schema_with(
          object_types_by_name: {},
          scalar_types_by_name: {},
          enum_types_by_name: {},
          index_definitions_by_name: {},
          schema_element_names: SchemaElementNames.new(form: :snake_case),
          graphql_extension_modules: [],
          static_script_ids_by_scoped_name: {}
        )
          Schema.new(
            object_types_by_name: object_types_by_name,
            scalar_types_by_name: scalar_types_by_name,
            enum_types_by_name: enum_types_by_name,
            index_definitions_by_name: index_definitions_by_name,
            schema_element_names: schema_element_names,
            graphql_extension_modules: graphql_extension_modules,
            static_script_ids_by_scoped_name: static_script_ids_by_scoped_name
          )
        end

        def object_type_with(
          update_targets: [],
          index_definition_names: [],
          graphql_fields_by_name: {},
          elasticgraph_category: nil,
          source_type: nil,
          graphql_only_return_type: false
        )
          ObjectType.new(
            index_definition_names: index_definition_names,
            update_targets: update_targets,
            graphql_fields_by_name: graphql_fields_by_name,
            elasticgraph_category: elasticgraph_category,
            source_type: source_type,
            graphql_only_return_type: graphql_only_return_type
          )
        end

        def derived_indexing_update_target_with(
          type: "DerivedIndexingUpdateTarget",
          relationship: nil,
          script_id: "some_script_id",
          id_source: "source_id",
          routing_value_source: "routing_value_source",
          rollover_timestamp_value_source: "rollover_timestamp_value_source",
          data_params: {},
          metadata_params: {}
        )
          UpdateTarget.new(
            type: type,
            relationship: relationship,
            script_id: script_id,
            id_source: id_source,
            routing_value_source: routing_value_source,
            rollover_timestamp_value_source: rollover_timestamp_value_source,
            data_params: data_params,
            metadata_params: metadata_params
          )
        end

        def normal_indexing_update_target_with(
          type: "UpdateTarget",
          relationship: SELF_RELATIONSHIP_NAME,
          id_source: "source_id",
          routing_value_source: "routing_value_source",
          rollover_timestamp_value_source: "rollover_timestamp_value_source",
          data_params: {},
          metadata_params: {}
        )
          UpdateTarget.new(
            type: type,
            relationship: relationship,
            script_id: INDEX_DATA_UPDATE_SCRIPT_ID,
            id_source: id_source,
            routing_value_source: routing_value_source,
            rollover_timestamp_value_source: rollover_timestamp_value_source,
            data_params: data_params,
            metadata_params: metadata_params
          )
        end

        def computation_detail_with(empty_bucket_value: 0, function: :sum)
          ComputationDetail.new(
            empty_bucket_value: empty_bucket_value,
            function: function
          )
        end

        def dynamic_param_with(source_path: "some_field", cardinality: :one)
          DynamicParam.new(source_path: source_path, cardinality: cardinality)
        end

        def static_param_with(value)
          StaticParam.new(value: value)
        end

        def index_definition_with(route_with: nil, rollover: nil, default_sort_fields: [], current_sources: [SELF_RELATIONSHIP_NAME], fields_by_path: {})
          IndexDefinition.new(
            route_with: route_with,
            rollover: rollover,
            default_sort_fields: default_sort_fields,
            current_sources: current_sources,
            fields_by_path: fields_by_path
          )
        end

        def index_field_with(source: SELF_RELATIONSHIP_NAME)
          IndexField.new(source: source)
        end

        def enum_type_with(values_by_name: {})
          Enum::Type.new(values_by_name: values_by_name)
        end

        def sort_field_with(field_path: "path.to.some.field", direction: :asc)
          SortField.new(
            field_path: field_path,
            direction: direction
          )
        end

        def relation_with(foreign_key: "some_id", direction: :asc, additional_filter: {}, foreign_key_nested_paths: [])
          Relation.new(foreign_key: foreign_key, direction: direction, additional_filter: additional_filter, foreign_key_nested_paths: foreign_key_nested_paths)
        end

        def graphql_field_with(name_in_index: "name_index", relation: nil, computation_detail: nil, resolver: nil)
          GraphQLField.new(
            computation_detail: computation_detail,
            name_in_index: name_in_index,
            relation: relation,
            resolver: resolver
          )
        end

        def scalar_type_with(
          coercion_adapter_ref: ScalarType::DEFAULT_COERCION_ADAPTER_REF,
          indexing_preparer_ref: ScalarType::DEFAULT_INDEXING_PREPARER_REF
        )
          ScalarType.new(
            coercion_adapter_ref: coercion_adapter_ref,
            indexing_preparer_ref: indexing_preparer_ref
          )
        end

        def scalar_coercion_adapter1
          Extension.new(ScalarCoercionAdapter1, "support/example_extensions/scalar_coercion_adapters", {})
        end

        def scalar_coercion_adapter2
          Extension.new(ScalarCoercionAdapter2, "support/example_extensions/scalar_coercion_adapters", {})
        end

        def indexing_preparer1
          Extension.new(IndexingPreparer1, "support/example_extensions/indexing_preparers", {})
        end

        def indexing_preparer2
          Extension.new(IndexingPreparer2, "support/example_extensions/indexing_preparers", {})
        end

        def graphql_extension_module1
          Extension.new(GraphQLExtensionModule1, "support/example_extensions/graphql_extension_modules", {})
        end
      end
    end
  end
end
