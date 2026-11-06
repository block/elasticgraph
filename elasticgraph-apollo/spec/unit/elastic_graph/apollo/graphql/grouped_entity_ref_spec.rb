# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/api_extension"
require "elastic_graph/apollo/graphql/apollo_entity_ref_resolver"
require "elastic_graph/graphql/aggregation/query_adapter"
require "elastic_graph/graphql/aggregation/resolvers/grouped_by"

module ElasticGraph
  module Apollo
    module GraphQL
      RSpec.describe "Automatically grouped Apollo entity references", :builds_graphql do
        let(:grouped_type_name) { "WidgetGroupedBy" }
        let(:derived_type_name_formats) { {} }
        let(:type_name_overrides) { {} }
        let(:reference_type) { "Component" }
        let(:source_id_field) { "indexed_component_id" }
        let(:id_indexing_only) { false }
        let(:source_id_type) { "ID" }
        let(:source_groupable) { nil }
        let(:reference_groupable) { nil }
        let(:include_size) { true }
        let(:tag_reference) { false }
        let(:identity_source) { false }
        let(:nested_identity) { false }
        let(:schema_artifacts) do
          generate_schema_artifacts(
            extension_modules: [SchemaDefinition::APIExtension],
            derived_type_name_formats: derived_type_name_formats,
            type_name_overrides: type_name_overrides
          ) do |schema|
            schema.object_type "Component" do |t|
              t.field "token", "ID!"
              t.apollo_key fields: "token", resolvable: false
            end
            if identity_source
              schema.object_type "Identity" do |t|
                t.field "component_id", "ID", name_in_index: "indexed_component_id"
              end
            end
            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "size", "Int" if include_size
              if identity_source
                t.field "identity", nested_identity ? "[Identity!]" : "Identity", name_in_index: "indexed_identity" do |f|
                  f.mapping type: "nested" if nested_identity
                end
              else
                t.field "component_id", source_id_type, name_in_index: "indexed_component_id",
                  indexing_only: id_indexing_only, groupable: source_groupable
              end
              t.index "widgets"
              t.apollo_entity_ref_field "component", reference_type, id_field_name_in_index: source_id_field do |f|
                f.groupable = reference_groupable unless reference_groupable.nil?
                f.tag_with "public" if tag_reference
              end
            end
          end
        end
        let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }
        let(:schema) { graphql.schema }
        let(:field) { schema.field_named(grouped_type_name, "component") }
        let(:resolver) { graphql.named_graphql_resolvers.fetch(field.resolver.name).call(field.resolver.config) }
        let(:adapter) do
          ElasticGraph::GraphQL::Aggregation::QueryAdapter.new(
            schema: schema,
            config: graphql.config,
            filter_args_translator: graphql.filter_args_translator,
            runtime_metadata: graphql.runtime_metadata,
            sub_aggregation_grouping_adapter: graphql.sub_aggregation_grouping_adapter
          )
        end

        context "with custom domain and derived type names" do
          let(:type_name_overrides) { {"Widget" => "RenamedWidget"} }
          let(:derived_type_name_formats) { {GroupedBy: "%{base}BucketKeys"} }
          let(:grouped_type_name) { "RenamedWidgetBucketKeys" }

          it "configures a grouping reference without depending on a GroupedBy name suffix" do
            expect(field.resolver.name).to eq(:apollo_entity_ref)
            expect(field.resolver.config).to include(scalar_grouping: true)
            expect(field.name_in_index).to eq("indexed_component_id")
          end
        end

        context "with an indexing-only source ID" do
          let(:id_indexing_only) { true }

          it "can group by the entity without exposing a scalar ID field" do
            expect(schema.type_named(grouped_type_name).graphql_type.fields).not_to include("component_id")
            expect(groupings_for(nodes_for("component { token }")).map(&:encoded_index_field_path))
              .to eq(["indexed_component_id"])
          end
        end

        context "with an indexing-only source ID and no other grouping fields" do
          let(:id_indexing_only) { true }
          let(:include_size) { false }

          it "creates a GroupedBy type for the automatically propagated reference" do
            expect(schema.type_named(grouped_type_name).graphql_type.fields.keys).to eq(["component"])
            expect(groupings_for(nodes_for("component { token }")).map(&:encoded_index_field_path))
              .to eq(["indexed_component_id"])
          end
        end

        context "with a non-null document reference" do
          let(:reference_type) { "Component!" }

          it "keeps the document reference non-null but makes the grouping reference nullable" do
            expect(schema.field_named("Widget", "component").type.name).to eq("Component!")
            expect(field.type.name).to eq("Component")
          end
        end

        context "with grouping disabled on the backing ID" do
          let(:source_groupable) { false }

          it "does not expose the reference in GroupedBy" do
            expect(schema.type_named(grouped_type_name).graphql_type.fields).not_to include("component", "component_id")
            expect(schema.field_named("Widget", "component").resolver.name).to eq(:apollo_entity_ref)
          end
        end

        context "with grouping disabled on the reference field" do
          let(:reference_groupable) { false }

          it "keeps the scalar ID grouping but does not propagate the reference" do
            expect(schema.type_named(grouped_type_name).graphql_type.fields).to include("component_id")
            expect(schema.type_named(grouped_type_name).graphql_type.fields).not_to include("component")
          end
        end

        context "with a list reference on the main type" do
          let(:reference_type) { "[Component!]" }
          let(:source_id_type) { "[ID!]" }

          it "does not automatically propagate list references" do
            expect(schema.type_named(grouped_type_name).graphql_type.fields).not_to include("component")
            expect(schema.field_named("Widget", "component").resolver.name).to eq(:apollo_entity_ref_list)
          end
        end

        context "with a dotted backing path through a groupable object" do
          let(:identity_source) { true }
          let(:source_id_field) { "indexed_identity.indexed_component_id" }

          it "groups the reference on the full indexed path" do
            expect(groupings_for(nodes_for("component { token }")).map(&:encoded_index_field_path))
              .to eq(["indexed_identity.indexed_component_id"])
          end
        end

        context "with a dotted backing path through a nested collection" do
          let(:identity_source) { true }
          let(:nested_identity) { true }
          let(:source_id_field) { "indexed_identity.indexed_component_id" }

          it "does not introduce an unsupported root grouping across a nested boundary" do
            expect(schema.type_named(grouped_type_name).graphql_type.fields).not_to include("component")
          end
        end

        context "with a tagged document reference" do
          let(:tag_reference) { true }

          it "propagates contract tags to the grouping reference" do
            grouped_field = schema.type_named(grouped_type_name).graphql_type.fields.fetch("component")
            expect(grouped_field.ast_node.directives.map(&:name)).to include("tag")
          end
        end

        def nodes_for(selection, fragments: "")
          query = schema.new_graphql_query(<<~QUERY)
            query {
              widget_aggregations(first: 10) {
                nodes { grouped_by { #{selection} } }
              }
            }
            #{fragments}
          QUERY
          expect(query.valid?).to be(true)
          query.lookahead.selection("widget_aggregations").selection("nodes")
        end

        def groupings_for(nodes, **options)
          adapter.send(:build_groupings_from, nodes, "widget_aggregations", **options).to_a
        end

        ["component { token __typename }", "component { __typename }"].each do |selection|
          it "groups on the backing ID for #{selection}" do
            groupings = groupings_for(nodes_for(selection))
            expect(groupings.map(&:key)).to eq(["component"])
            expect(groupings.map(&:encoded_index_field_path)).to eq(["indexed_component_id"])
          end
        end

        it "keeps scalar ID grouping available alongside the entity reference" do
          groupings = groupings_for(nodes_for("component_id component { token }"))
          expect(groupings.map(&:key)).to contain_exactly("component_id", "component")
          expect(groupings.map(&:encoded_index_field_path)).to eq(["indexed_component_id", "indexed_component_id"])
        end

        it "supports entity selections inside a fragment" do
          nodes = nodes_for("...ComponentGroup", fragments: <<~QUERY)
            fragment ComponentGroup on WidgetGroupedBy {
              component { token }
            }
          QUERY
          expect(groupings_for(nodes).map(&:encoded_index_field_path)).to eq(["indexed_component_id"])
        end

        ["component { token }", "ref: component { id_alias: token __typename }"].each do |selection|
          it "resolves the selected bucket key for #{selection}" do
            nodes = nodes_for(selection)
            grouping = groupings_for(nodes).first
            lookahead = nodes.selection("grouped_by").selections.first
            object = ElasticGraph::GraphQL::Aggregation::Resolvers::GroupedBy.new({"key" => {grouping.key => "c1"}}, [])
            expect(resolver.resolve(field: field, object: object, args: {}, context: {}, lookahead: lookahead))
              .to eq("token" => "c1")
          end
        end

        it "resolves missing-value buckets to null" do
          lookahead = nodes_for("component { token }").selection("grouped_by").selection("component")
          object = ElasticGraph::GraphQL::Aggregation::Resolvers::GroupedBy.new({"key" => {"component" => nil}}, [])
          expect(resolver.resolve(field: field, object: object, args: {}, context: {}, lookahead: lookahead)).to be_nil
        end

        it "keeps document reference resolution unchanged" do
          allow(datastore_client).to receive(:msearch).and_return({"responses" => [{
            "took" => 0,
            "timed_out" => false,
            "_shards" => {"total" => 1, "successful" => 1, "skipped" => 0, "failed" => 0},
            "hits" => {
              "total" => {"value" => 1, "relation" => "eq"},
              "hits" => [{
                "_index" => "widgets",
                "_id" => "w1",
                "_source" => {"id" => "w1", "indexed_component_id" => "c1"},
                "sort" => ["w1"]
              }]
            },
            "status" => 200
          }]})
          response = graphql.graphql_query_executor.execute(<<~QUERY)
            query { widgets { nodes { id component { __typename token } } } }
          QUERY
          expect(response["errors"]).to eq(nil).or eq([])
          expect(response.dig("data", "widgets", "nodes")).to eq([{
            "id" => "w1", "component" => {"__typename" => "Component", "token" => "c1"}
          }])
        end

        it "executes the generated resolver with scalar grouping, aliases, typename, and cursor pagination" do
          bucket_for = ->(id, count) do
            {"key" => {"component_id" => id, "ref" => id}, "doc_count" => count}
          end
          response_for = ->(buckets) do
            {"responses" => [{
              "took" => 0,
              "timed_out" => false,
              "_shards" => {"total" => 1, "successful" => 1, "skipped" => 0, "failed" => 0},
              "hits" => {"total" => {"value" => 3, "relation" => "eq"}, "hits" => []},
              "aggregations" => {"widget_aggregations" => {"buckets" => buckets}},
              "status" => 200
            }]}
          end
          allow(datastore_client).to receive(:msearch).and_return(
            response_for.call([bucket_for.call("c1", 2), bucket_for.call("c2", 1)]),
            response_for.call([bucket_for.call("c2", 1)])
          )
          query = <<~QUERY
            query Groups($after: Cursor) {
              widget_aggregations(first: 1, after: $after) {
                nodes {
                  grouped_by {
                    component_id
                    ref: component { __typename id_alias: token }
                  }
                  count
                }
                page_info { has_next_page end_cursor }
              }
            }
          QUERY
          first = graphql.graphql_query_executor.execute(query)
          expect(first["errors"]).to eq(nil).or eq([])
          first_page = first.dig("data", "widget_aggregations")
          expect(first_page.fetch("nodes")).to eq([{
            "grouped_by" => {"component_id" => "c1", "ref" => {"__typename" => "Component", "id_alias" => "c1"}},
            "count" => 2
          }])
          expect(first_page.dig("page_info", "has_next_page")).to be(true)
          cursor = first_page.dig("page_info", "end_cursor")
          expect(cursor).not_to be_nil

          second = graphql.graphql_query_executor.execute(query, variables: {"after" => cursor})
          expect(second["errors"]).to eq(nil).or eq([])
          second_page = second.dig("data", "widget_aggregations")
          expect(second_page.fetch("nodes")).to eq([{
            "grouped_by" => {"component_id" => "c2", "ref" => {"__typename" => "Component", "id_alias" => "c2"}},
            "count" => 1
          }])
          expect(second_page.dig("page_info", "has_next_page")).to be(false)
        end

        it "uses the full parent path for nested grouping and reference resolution" do
          path = [ElasticGraph::GraphQL::Aggregation::PathSegment.new("parent_alias", "indexed_parent")]
          nodes = nodes_for("ref: component { token }")
          grouping = groupings_for(nodes, from_field_path: path).first
          expect(grouping.encoded_index_field_path).to eq("indexed_parent.indexed_component_id")
          expect(grouping.key).to eq("parent_alias.ref")
          object = ElasticGraph::GraphQL::Aggregation::Resolvers::GroupedBy.new({"key" => {grouping.key => "c1"}}, path)
          lookahead = nodes.selection("grouped_by").selections.first
          expect(resolver.resolve(field: field, object: object, args: {}, context: {}, lookahead: lookahead))
            .to eq("token" => "c1")
        end
      end
    end
  end
end
