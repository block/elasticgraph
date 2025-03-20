# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/update_target"
require "elastic_graph/schema_artifacts/runtime_metadata/graphql_field"
require "elastic_graph/schema_artifacts/runtime_metadata/index_definition"
require "elastic_graph/schema_artifacts/runtime_metadata/index_field"
require "elastic_graph/schema_artifacts/runtime_metadata/object_type"
require "elastic_graph/schema_artifacts/runtime_metadata/scalar_type"
require "elastic_graph/schema_artifacts/runtime_metadata/schema"
require "elastic_graph/spec_support/runtime_metadata_support"
require "elastic_graph/spec_support/example_extensions/graphql_resolvers"
require "support/example_extensions/graphql_extension_modules"
require "support/example_extensions/indexing_preparers"
require "support/example_extensions/scalar_coercion_adapters"
require "yaml"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe Schema do
        include RuntimeMetadataSupport

        it "can roundtrip a schema through a primitive ruby hash for easy serialization and deserialization" do
          schema = Schema.new(
            object_types_by_name: {
              "Widget" => ObjectType.new(
                index_definition_names: ["widgets"],
                update_targets: [
                  UpdateTarget.new(
                    type: "WidgetCurrency",
                    relationship: "currency",
                    script_id: "some_script_id",
                    id_source: "cost.currency",
                    routing_value_source: "cost.currency_name",
                    rollover_timestamp_value_source: "currency_introduced_on",
                    data_params: {"workspace_id" => DynamicParam.new(source_path: "wid", cardinality: :one)},
                    metadata_params: {"relationshipName" => StaticParam.new(value: "currency")}
                  ),
                  UpdateTarget.new(
                    type: nil,
                    relationship: nil,
                    script_id: nil,
                    id_source: "id",
                    routing_value_source: nil,
                    rollover_timestamp_value_source: nil,
                    data_params: {},
                    metadata_params: {}
                  )
                ],
                graphql_fields_by_name: {
                  "name_graphql" => GraphQLField.new(
                    computation_detail: nil,
                    name_in_index: "name_index",
                    relation: nil,
                    resolver: :self
                  ),
                  "parent" => GraphQLField.new(
                    computation_detail: nil,
                    name_in_index: "parent",
                    relation: Relation.new(
                      foreign_key: "grandparents.parents.some_id",
                      direction: :out,
                      additional_filter: {"flag_field" => {"equalToAnyOf" => [true]}},
                      foreign_key_nested_paths: ["grandparents", "grandparents.parents"]
                    ),
                    resolver: :self
                  ),
                  "sum" => GraphQLField.new(
                    computation_detail: ComputationDetail.new(
                      empty_bucket_value: 0,
                      function: :sum
                    ),
                    name_in_index: "sum",
                    relation: nil,
                    resolver: :self
                  )
                },
                elasticgraph_category: :some_category,
                source_type: "SomeType",
                graphql_only_return_type: true
              )
            },
            scalar_types_by_name: {
              "ScalarType1" => ScalarType.new(
                scalar_coercion_adapter1.to_dumpable_hash,
                indexing_preparer1.to_dumpable_hash
              ),
              "ScalarType2" => ScalarType.new(
                scalar_coercion_adapter2.to_dumpable_hash,
                indexing_preparer2.to_dumpable_hash
              )
            },
            enum_types_by_name: {
              "WidgetSort" => Enum::Type.new({
                "id_ASC" => Enum::Value.new(SortField.new("id", :asc), nil, nil, nil),
                "id_DESC" => Enum::Value.new(SortField.new("id", :desc), nil, nil, nil)
              }),
              "DateGroupingGranularity" => Enum::Type.new({
                "DAY" => Enum::Value.new(nil, "day", nil, "DAILY"),
                "YEAR" => Enum::Value.new(nil, "year", nil, "YEARLY")
              }),
              "DistanceUnit" => Enum::Type.new({
                "MILE" => Enum::Value.new(nil, nil, :mi, nil),
                "KILOMETER" => Enum::Value.new(nil, nil, :km, nil)
              })
            },
            index_definitions_by_name: {
              "widgets" => IndexDefinition.new(
                route_with: nil,
                rollover: IndexDefinition::Rollover.new(:monthly, "created_at"),
                default_sort_fields: [
                  SortField.new("path.to.field1", :desc),
                  SortField.new("path.to.field2", :asc)
                ],
                current_sources: [SELF_RELATIONSHIP_NAME],
                fields_by_path: {
                  "foo.bar" => IndexField.new(source: "other")
                }
              ),
              "addresses" => IndexDefinition.new(
                route_with: nil,
                rollover: IndexDefinition::Rollover.new(:yearly, nil),
                default_sort_fields: [],
                current_sources: [SELF_RELATIONSHIP_NAME],
                fields_by_path: {}
              ),
              "components" => IndexDefinition.new(
                route_with: "group_id",
                rollover: nil,
                default_sort_fields: [],
                current_sources: [SELF_RELATIONSHIP_NAME],
                fields_by_path: {}
              )
            },
            schema_element_names: SchemaElementNames.new(
              form: :snake_case,
              overrides: {"any_of" => "or"}
            ),
            graphql_extension_modules: [graphql_extension_module1],
            graphql_resolvers_by_name: {resolver1: graphql_resolver1(limit: 10)},
            static_script_ids_by_scoped_name: {
              "filter/time_of_day" => "time_of_day_4474b200b6a00f385ed49f7c9669cbf3"
            }
          )

          hash = schema.to_dumpable_hash

          expect(hash).to eq(
            "object_types_by_name" => {
              "Widget" => {
                "index_definition_names" => ["widgets"],
                "update_targets" => [
                  {
                    "type" => "WidgetCurrency",
                    "relationship" => "currency",
                    "script_id" => "some_script_id",
                    "id_source" => "cost.currency",
                    "routing_value_source" => "cost.currency_name",
                    "rollover_timestamp_value_source" => "currency_introduced_on",
                    "data_params" => {"workspace_id" => {"source_path" => "wid", "cardinality" => "one"}},
                    "metadata_params" => {"relationshipName" => {"value" => "currency"}}
                  },
                  {
                    "id_source" => "id"
                  }
                ],
                "graphql_fields_by_name" => {
                  "name_graphql" => {
                    "name_in_index" => "name_index",
                    "resolver" => "self"
                  },
                  "parent" => {
                    "relation" => {
                      "foreign_key" => "grandparents.parents.some_id",
                      "direction" => "out",
                      "additional_filter" => {"flag_field" => {"equalToAnyOf" => [true]}},
                      "foreign_key_nested_paths" => ["grandparents", "grandparents.parents"]
                    },
                    "resolver" => "self"
                  },
                  "sum" => {
                    "computation_detail" => {
                      "empty_bucket_value" => 0,
                      "function" => "sum"
                    },
                    "resolver" => "self"
                  }
                },
                "elasticgraph_category" => "some_category",
                "source_type" => "SomeType",
                "graphql_only_return_type" => true
              }
            },
            "scalar_types_by_name" => {
              "ScalarType1" => {
                "coercion_adapter" => {
                  "extension_name" => "ElasticGraph::SchemaArtifacts::ScalarCoercionAdapter1",
                  "require_path" => "support/example_extensions/scalar_coercion_adapters"
                },
                "indexing_preparer" => {
                  "extension_name" => "ElasticGraph::SchemaArtifacts::IndexingPreparer1",
                  "require_path" => "support/example_extensions/indexing_preparers"
                }
              },
              "ScalarType2" => {
                "coercion_adapter" => {
                  "extension_name" => "ElasticGraph::SchemaArtifacts::ScalarCoercionAdapter2",
                  "require_path" => "support/example_extensions/scalar_coercion_adapters"
                },
                "indexing_preparer" => {
                  "extension_name" => "ElasticGraph::SchemaArtifacts::IndexingPreparer2",
                  "require_path" => "support/example_extensions/indexing_preparers"
                }
              }
            },
            "enum_types_by_name" => {
              "WidgetSort" => {
                "values_by_name" => {
                  "id_ASC" => {"sort_field" => {
                    "field_path" => "id",
                    "direction" => "asc"
                  }},
                  "id_DESC" => {"sort_field" => {
                    "field_path" => "id",
                    "direction" => "desc"
                  }}
                }
              },
              "DateGroupingGranularity" => {
                "values_by_name" => {
                  "DAY" => {"datastore_value" => "day", "alternate_original_name" => "DAILY"},
                  "YEAR" => {"datastore_value" => "year", "alternate_original_name" => "YEARLY"}
                }
              },
              "DistanceUnit" => {
                "values_by_name" => {
                  "MILE" => {"datastore_abbreviation" => "mi"},
                  "KILOMETER" => {"datastore_abbreviation" => "km"}
                }
              }
            },
            "index_definitions_by_name" => {
              "widgets" => {
                "rollover" => {"frequency" => "monthly", "timestamp_field_path" => "created_at"},
                "default_sort_fields" => [
                  {"field_path" => "path.to.field1", "direction" => "desc"},
                  {"field_path" => "path.to.field2", "direction" => "asc"}
                ],
                "current_sources" => [SELF_RELATIONSHIP_NAME],
                "fields_by_path" => {
                  "foo.bar" => {
                    "source" => "other"
                  }
                }
              },
              "addresses" => {
                "rollover" => {"frequency" => "yearly"},
                "current_sources" => [SELF_RELATIONSHIP_NAME]
              },
              "components" => {
                "route_with" => "group_id",
                "current_sources" => [SELF_RELATIONSHIP_NAME]
              }
            },
            "schema_element_names" => {
              "form" => "snake_case",
              "overrides" => {"any_of" => "or"}
            },
            "graphql_extension_modules" => [{
              "extension_name" => "ElasticGraph::SchemaArtifacts::GraphQLExtensionModule1",
              "require_path" => "support/example_extensions/graphql_extension_modules"
            }],
            "graphql_resolvers_by_name" => {
              "resolver1" => {
                "extension_name" => "ElasticGraph::GraphQLResolver1",
                "require_path" => "elastic_graph/spec_support/example_extensions/graphql_resolvers",
                "extension_config" => {"limit" => 10}
              }
            },
            "static_script_ids_by_scoped_name" => {
              "filter/time_of_day" => "time_of_day_4474b200b6a00f385ed49f7c9669cbf3"
            }
          )

          expect(Schema.from_hash(hash, for_context: :graphql)).to eq schema
        end

        it "ignores object types that have no meaningful runtime metadata" do
          schema = schema_with(object_types_by_name: {
            "UpdateTargetsOnly" => object_type_with(update_targets: [UpdateTarget.new(
              type: "WidgetCurrency",
              relationship: "currency",
              script_id: "some_script_id",
              id_source: "cost.currency",
              routing_value_source: nil,
              rollover_timestamp_value_source: nil,
              data_params: {"workspace_id" => dynamic_param_with(cardinality: :many)},
              metadata_params: {}
            )]),
            "IndexDefinitionNamesOnly" => object_type_with(index_definition_names: ["foo", "bar"]),
            "FieldsByGraphQLOnly" => object_type_with(graphql_fields_by_name: {
              "name_graphql" => GraphQLField.new(
                name_in_index: "name_index",
                computation_detail: nil,
                relation: nil,
                resolver: :self
              )
            }),
            "NoMetadata" => object_type_with
          })

          schema = Schema.from_hash(schema.to_dumpable_hash, for_context: :graphql)

          expect(schema.object_types_by_name.keys).to contain_exactly(
            "UpdateTargetsOnly",
            "IndexDefinitionNamesOnly",
            "FieldsByGraphQLOnly"
          )
        end

        it "ignores enum types that have no meaningful runtime metadata" do
          schema = schema_with(enum_types_by_name: {
            "HasValues" => enum_type_with(values_by_name: {
              "id_ASC" => Enum::Value.new(SortField.new("id", :asc), nil, nil, nil),
              "id_DESC" => Enum::Value.new(SortField.new("id", :desc), nil, nil, nil)
            }),
            "NoValues" => enum_type_with(values_by_name: {})
          })

          schema = Schema.from_hash(schema.to_dumpable_hash, for_context: :graphql)

          expect(schema.enum_types_by_name.keys).to contain_exactly("HasValues")
        end

        it "builds from a minimal hash" do
          schema = Schema.from_hash({
            "schema_element_names" => {"form" => "camelCase"}
          }, for_context: :graphql)

          expect(schema).to eq Schema.new(
            object_types_by_name: {},
            scalar_types_by_name: {},
            enum_types_by_name: {},
            index_definitions_by_name: {},
            schema_element_names: SchemaElementNames.from_hash({"form" => "camelCase"}),
            graphql_extension_modules: [],
            graphql_resolvers_by_name: {},
            static_script_ids_by_scoped_name: {}
          )
        end

        it "only loads `graphql_extension_modules` for the `:graphql` context since the extension module gems may not be available in other contexts" do
          schema = schema_with(graphql_extension_modules: [graphql_extension_module1])

          expect(Schema.from_hash(schema.to_dumpable_hash, for_context: :admin).graphql_extension_modules).to eq []
          expect(Schema.from_hash(schema.to_dumpable_hash, for_context: :indexer).graphql_extension_modules).to eq []
          expect(Schema.from_hash(schema.to_dumpable_hash, for_context: :graphql).graphql_extension_modules).to eq [graphql_extension_module1]
        end

        it "dumps all hashes in alphabetical order for consistency" do
          full_dumped_runtime_metadata = ::YAML.safe_load_file(::File.join(
            CommonSpecHelpers::REPO_ROOT, "config", "schema", "artifacts", RUNTIME_METADATA_FILE
          ))

          expect(paths_to_non_alphabetical_hashes_in(full_dumped_runtime_metadata)).to eq []
        end

        def paths_to_non_alphabetical_hashes_in(hash, parent_path: [])
          paths = []
          # :nocov: -- only fully covered when the test above fails
          if hash.keys != hash.keys.sort
            paths << (parent_path.empty? ? "<ROOT>" : parent_path.join("."))
          end
          # :nocov:

          hash.flat_map do |key, value|
            if value.is_a?(::Hash)
              paths_to_non_alphabetical_hashes_in(value, parent_path: parent_path + [key])
            else
              []
            end
          end + paths
        end
      end
    end
  end
end
