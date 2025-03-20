# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition"
require "elastic_graph/errors"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      RSpec.shared_examples_for "an IndexDefinition implementation (unit specs)" do
        include SchemaArtifacts::RuntimeMetadata::RuntimeMetadataSupport

        context "when instantiated without a config index definition" do
          it "raises an error" do
            datastore_core = define_datastore_core_with_index "my_type", config_overrides: {index_definitions: {}}

            expect {
              datastore_core.index_definitions_by_name
            }.to raise_error Errors::ConfigError, a_string_including("does not provide an index definition for `my_type`")
          end
        end

        it "exposes `use_updates_for_indexing?` based on index config" do
          index = define_index("my_type", config_overrides: {
            index_definitions: {"my_type" => config_index_def_of(use_updates_for_indexing: true)}
          })

          expect(index.use_updates_for_indexing?).to be true

          index = define_index("my_type", config_overrides: {
            index_definitions: {"my_type" => config_index_def_of(use_updates_for_indexing: false)}
          })

          expect(index.use_updates_for_indexing?).to be false
        end

        describe "#index_expression_for_search" do
          it "returns the index expression to search" do
            index_def = define_index("items")

            expect(index_def.index_expression_for_search).to start_with("items")
          end
        end

        describe "#flattened_env_setting_overrides" do
          it "returns flattened environment-specific overrides from config" do
            config_overrides = {
              index_definitions: {
                "my_type" => config_index_def_of(setting_overrides: {
                  "number_of_replicas" => 7,
                  "yet" => {"another" => {"setting" => true}}
                })
              }
            }

            datastore_core = define_datastore_core_with_index "my_type",
              number_of_replicas: 2,
              mapping: {coerce: true},
              some: {other_setting: false},
              config_overrides: config_overrides

            index_def = datastore_core.index_definitions_by_name.fetch("my_type")

            expect(index_def.flattened_env_setting_overrides).to include(
              "index.number_of_replicas" => 7,
              "index.yet.another.setting" => true
            )
          end
        end

        describe "#cluster_to_query" do
          it "references query_cluster from config" do
            index = define_index("my_type", config_overrides: {index_definitions: {
              "my_type" => config_index_def_of(query_cluster: "my_type_cluster")
            }})

            expect(index.cluster_to_query).to eq("my_type_cluster")
          end

          it "returns `nil` when query_cluster is nil" do
            index = define_index("my_type", config_overrides: {index_definitions: {
              "my_type" => config_index_def_of(query_cluster: nil)
            }})

            expect(index.cluster_to_query).to eq(nil)
          end
        end

        describe "#all_accessible_cluster_names" do
          it "includes all cluster names from both `index_into_clusters` and `query_cluster`" do
            cluster_names = all_accessible_cluster_names_for_config(
              clusters: {
                "a" => cluster_of,
                "b" => cluster_of,
                "c" => cluster_of
              },
              index_definitions: {
                "my_type" => config_index_def_of(
                  index_into_clusters: ["a", "b"],
                  query_cluster: "c"
                )
              }
            )

            expect(cluster_names).to contain_exactly("a", "b", "c")
          end

          it "removes duplicates" do
            cluster_names = all_accessible_cluster_names_for_config(
              clusters: {
                "a" => cluster_of,
                "b" => cluster_of
              },
              index_definitions: {
                "my_type" => config_index_def_of(
                  index_into_clusters: ["a", "b"],
                  query_cluster: "a"
                )
              }
            )

            expect(cluster_names).to contain_exactly("a", "b")
          end

          it "ignores `query_cluster` when it is nil" do
            cluster_names = all_accessible_cluster_names_for_config(
              clusters: {
                "a" => cluster_of,
                "b" => cluster_of
              },
              index_definitions: {
                "my_type" => config_index_def_of(
                  index_into_clusters: ["a", "b"],
                  query_cluster: nil
                )
              }
            )

            expect(cluster_names).to contain_exactly("a", "b")
          end

          it "excludes cluster names that are referenced from an index definition but undefined as a cluster" do
            cluster_names = all_accessible_cluster_names_for_config(
              clusters: {
                "a" => cluster_of,
                "c" => cluster_of
              },
              index_definitions: {
                "my_type" => config_index_def_of(
                  index_into_clusters: ["a", "b"],
                  query_cluster: "c"
                )
              }
            )

            expect(cluster_names).to contain_exactly("a", "c")
          end

          def all_accessible_cluster_names_for_config(clusters:, index_definitions:)
            define_index("my_type", config_overrides: {
              clusters: clusters,
              index_definitions: index_definitions,
              clients_by_name: clusters.transform_values { stubbed_datastore_client }
            }).all_accessible_cluster_names
          end
        end

        describe "#accessible_cluster_names_to_index_into" do
          it "includes cluster names from `index_into_clusters` but not from `query_cluster`" do
            cluster_names = accessible_cluster_names_to_index_into_for_config(
              clusters: {
                "a" => cluster_of,
                "b" => cluster_of,
                "c" => cluster_of
              },
              index_definitions: {
                "my_type" => config_index_def_of(
                  index_into_clusters: ["a", "b"],
                  query_cluster: "c"
                )
              }
            )

            expect(cluster_names).to contain_exactly("a", "b")
          end

          it "excludes cluster names that are referenced from an index definition but undefined as a cluster" do
            cluster_names = accessible_cluster_names_to_index_into_for_config(
              clusters: {
                "a" => cluster_of,
                "c" => cluster_of
              },
              index_definitions: {
                "my_type" => config_index_def_of(
                  index_into_clusters: ["a", "b"],
                  query_cluster: "c"
                )
              }
            )

            expect(cluster_names).to contain_exactly("a")
          end

          def accessible_cluster_names_to_index_into_for_config(clusters:, index_definitions:)
            define_index("my_type", config_overrides: {
              clusters: clusters,
              index_definitions: index_definitions,
              clients_by_name: clusters.transform_values { stubbed_datastore_client }
            }).accessible_cluster_names_to_index_into
          end
        end

        describe "#clusters_to_index_into" do
          it "references index_into_clusters from config" do
            index = define_index("my_type", config_overrides: {
              index_definitions: {
                "my_type" => config_index_def_of(index_into_clusters: ["a", "b"])
              }
            })

            expect(index.clusters_to_index_into).to contain_exactly("a", "b")
          end

          it "raises an error when index_into_clusters is nil" do
            index = define_index("my_type", config_overrides: {
              index_definitions: {
                "my_type" => config_index_def_of(index_into_clusters: nil)
              }
            })

            expect {
              index.clusters_to_index_into
            }.to raise_error(Errors::ConfigError, a_string_including("index_into_clusters"))
          end

          it "allows it to be set to an empty list as a way to disable the application from being able to index that type" do
            index = define_index("my_type", config_overrides: {
              index_definitions: {
                "my_type" => config_index_def_of(index_into_clusters: [])
              }
            })

            expect(index.clusters_to_index_into).to eq []
          end
        end

        describe "#ignored_values_for_routing" do
          it "returns a list of ignored routing_values from the index config" do
            index = define_index("my_type", config_overrides: {
              index_definitions: {
                "my_type" => config_index_def_of(ignore_routing_values: ["value"])
              }
            })

            expect(index.ignored_values_for_routing).to eq Set.new(["value"])
          end
        end

        describe "#route_with" do
          it "returns the field used for routing" do
            index = define_index do |i|
              i.route_with "name"
            end

            expect(index.route_with).to eq "name"
          end
        end

        describe "#current_sources" do
          it "returns the current sources that flow into an index" do
            index = define_index

            expect(index.current_sources).to contain_exactly SELF_RELATIONSHIP_NAME
          end
        end

        describe "#fields_by_path" do
          it "returns the `fields_by_path` from the runtime metadata" do
            index = define_index

            expect(index.fields_by_path).to include({
              "created_at" => index_field_with,
              "id" => index_field_with,
              "name" => index_field_with,
              "nested_fields.nested_id" => index_field_with
            })
          end
        end

        describe "#routing_value_for_prepared_record" do
          it "returns `nil` if the index does not use custom routing" do
            index = define_index

            expect(index.routing_value_for_prepared_record({"id" => 17, "name" => "Joe"})).to eq nil
          end

          it "returns the value of the field used for custom routing when custom routing is used" do
            index = define_index do |i|
              i.route_with "name"
            end

            expect(index.routing_value_for_prepared_record({"id" => 17, "name" => "Joe"})).to eq "Joe"
          end

          it "resolves a nested routing field to a nested value" do
            index = define_index do |i|
              i.route_with "nested_fields.nested_id"
            end

            expect(index.routing_value_for_prepared_record({"id" => 17, "name" => "Joe", "nested_fields" => {"nested_id" => "12"}})).to eq "12"
          end

          it "returns the value as a string even if it wasn't originally since the datastore routing uses string values" do
            index = define_index do |i|
              i.route_with "nested_fields.nested_id"
            end

            expect(index.routing_value_for_prepared_record({"id" => 17, "name" => "Joe", "nested_fields" => {"nested_id" => 12}})).to eq "12"
          end

          it "returns the `id` value (as a string) if the custom routing value is configured as an ignored routing value" do
            index = define_index("my_type", config_overrides: {index_definitions: {
              "my_type" => config_index_def_of(ignore_routing_values: ["Joe"])
            }}) do |i|
              i.route_with "name"
            end

            expect(index.routing_value_for_prepared_record({"id" => 17, "name" => "Joe"})).to eq "17"
            expect(index.routing_value_for_prepared_record({"id" => 17, "name" => "Bob"})).to eq "Bob"
          end

          it "allows the `route_with_path` to be provided by the caller to support cases where the source event is of a different type" do
            index = define_index do |i|
              i.route_with "name"
            end

            record = {"id" => 17, "name" => "Joe", "nested" => {"alternate_name" => "Joseph"}}
            expect(index.routing_value_for_prepared_record(record, route_with_path: "nested.alternate_name")).to eq "Joseph"
          end

          it "allows the `id_path` to be provided by the caller to support cases where the source event is of a different type" do
            index = define_index("my_type", config_overrides: {index_definitions: {
              "my_type" => config_index_def_of(ignore_routing_values: ["Joseph"])
            }}) do |i|
              i.route_with "name"
            end

            record = {"id" => 17, "name" => "Joe", "nested" => {"alternate_name" => "Joseph", "alt_id" => 12}}
            expect(index.routing_value_for_prepared_record(record, route_with_path: "nested.alternate_name", id_path: "nested.alt_id")).to eq "12"
          end

          it "raises an error if `route_with_path` is `nil` while there is custom routing configured" do
            index = define_index do |i|
              i.route_with "name"
            end

            record = {"id" => 17, "name" => "Joe", "nested" => {"alternate_name" => "Joseph"}}
            expect {
              index.routing_value_for_prepared_record(record, route_with_path: nil)
            }.to raise_error a_string_including("my_type", "`route_with_path` is misconfigured (was `nil`)")
          end

          it "ignores `route_with_path: nil` when custom routing is not used" do
            index = define_index

            expect(index.routing_value_for_prepared_record({"id" => 17, "name" => "Joe"}, route_with_path: nil)).to eq nil
          end
        end

        describe "#default_sort_clauses" do
          it "returns the configured default sort fields in datastore sort clause form" do
            index = define_index do |i|
              i.default_sort "name", :asc, "created_at", :desc
            end

            expect(index.default_sort_clauses).to eq [
              {"name" => {"order" => "asc"}},
              {"created_at" => {"order" => "desc"}}
            ]
          end
        end

        describe "#accessible_from_queries?" do
          it "returns `true` when `cluster_to_query` references a main cluster" do
            index = define_index("my_type", config_overrides: {
              clusters: {"main" => cluster_of},
              index_definitions: {"my_type" => config_index_def_of(query_cluster: "main")}
            })

            expect(index.accessible_from_queries?).to be true
          end

          it "returns `false` when `cluster_to_query` references an undefined cluster" do
            index = define_index("my_type", config_overrides: {
              clusters: {"main" => cluster_of},
              index_definitions: {"my_type" => config_index_def_of(query_cluster: "undefined")}
            })

            expect(index.accessible_from_queries?).to be false
          end

          it "returns `false` when `cluster_to_query` is nil" do
            index = define_index("my_type", config_overrides: {
              clusters: {"main" => cluster_of},
              index_definitions: {"my_type" => config_index_def_of(query_cluster: nil)}
            })

            expect(index.accessible_from_queries?).to be false
          end
        end

        describe "#list_counts_field_paths_for_source" do
          it "returns an empty set for an index definition that has no list fields" do
            index = define_index

            expect(index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)).to eq ::Set.new
          end

          it "returns the paths to the `#{LIST_COUNTS_FIELD}` subfields" do
            index = define_index(schema_def: lambda do |schema|
              update_type_for_index(schema) do |t|
                t.field "ints", "[Int]"
                t.field "strings", "[String]"
              end
            end)

            expect(index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)).to eq [
              "#{LIST_COUNTS_FIELD}.ints",
              "#{LIST_COUNTS_FIELD}.strings"
            ].to_set
          end

          it "omits list count field paths that are populated by a different source" do
            index = define_index(schema_def: lambda do |schema|
              schema.object_type "RelatedThing" do |t|
                t.field "id", "ID"
                t.field "created_at", "DateTime"
                t.field "strings", "[String]"
                t.index "related_things"
              end

              update_type_for_index(schema) do |t|
                t.relates_to_one "related_thing", "RelatedThing", via: "id", dir: :in do |r|
                  r.equivalent_field "created_at"
                end
                t.field "ints", "[Int]"
                t.field "strings", "[String]" do |f|
                  f.sourced_from "related_thing", "strings"
                end
              end
            end)

            expect(index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)).to eq [
              "#{LIST_COUNTS_FIELD}.ints"
            ].to_set

            expect(index.list_counts_field_paths_for_source("related_thing")).to eq [
              "#{LIST_COUNTS_FIELD}.strings"
            ].to_set
          end

          it "includes the paths to nested `#{LIST_COUNTS_FIELD}` subfields" do
            index = define_index(schema_def: lambda do |schema|
              schema.object_type "OtherType" do |t|
                t.field "strings", "[String]"
              end

              update_type_for_index(schema) do |t|
                t.field "ints", "[Int]"
                t.field "nesteds", "[OtherType]" do |f|
                  f.mapping type: "nested"
                end
                t.field "objects", "[OtherType]" do |f|
                  f.mapping type: "object"
                end
              end
            end)

            expect(index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)).to eq [
              "#{LIST_COUNTS_FIELD}.ints",
              "#{LIST_COUNTS_FIELD}.nesteds",
              "#{LIST_COUNTS_FIELD}.objects",
              "#{LIST_COUNTS_FIELD}.objects|strings",
              "nesteds.#{LIST_COUNTS_FIELD}.strings"
            ].to_set
          end

          it "omits fields that happen to contain `#{LIST_COUNTS_FIELD}` within their name" do
            index = define_index(schema_def: lambda do |schema|
              update_type_for_index(schema) do |t|
                t.field "ints", "[Int]"
                t.field "string#{LIST_COUNTS_FIELD}", "String"
              end
            end)

            expect(index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)).to eq [
              "#{LIST_COUNTS_FIELD}.ints"
            ].to_set
          end

          it "memoizes the result to not waste time recomputing the same set later" do
            index = define_index(schema_def: lambda do |schema|
              schema.object_type "RelatedThing" do |t|
                t.field "id", "ID"
                t.field "strings", "[String]"
                t.field "created_at", "DateTime"
                t.index "related_things"
              end

              update_type_for_index(schema) do |t|
                t.relates_to_one "related_thing", "RelatedThing", via: "id", dir: :in do |r|
                  r.equivalent_field "created_at"
                end
                t.field "ints", "[Int]"
                t.field "strings", "[String]" do |f|
                  f.sourced_from "related_thing", "strings"
                end
              end
            end)

            expect(index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)).to be(
              index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)
            ).and differ_from(
              index.list_counts_field_paths_for_source("related_thing")
            )

            expect(index.list_counts_field_paths_for_source("related_thing")).to be(
              index.list_counts_field_paths_for_source("related_thing")
            ).and differ_from(
              index.list_counts_field_paths_for_source(SELF_RELATIONSHIP_NAME)
            )
          end

          def update_type_for_index(schema)
            yield schema.state.object_types_by_name.fetch("MyType")
          end
        end

        def define_index(name = "my_type", **options, &block)
          define_datastore_core_with_index(name, **options, &block)
            .index_definitions_by_name.fetch(name)
        end
      end
    end
  end
end
