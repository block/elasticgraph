# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_details_tracker"
require "elastic_graph/graphql/resolvers/nested_relationships_source"
require "graphql"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe NestedRelationshipsSource, :factories, :uses_datastore, :capture_logs do
        include AggregationsHelpers
        let(:merged_queries_message_type) { "NestedRelationshipsMergedQueries" }

        context "when `nested_relationship_resolver_mode` is set to `optimized`" do
          let(:graphql) { build_graphql(nested_relationship_resolver_mode: :optimized) }

          it "allows a single query to be run with multiple filter value sets" do
            index_into(
              graphql,
              build(:widget, id: "w1", component_ids: ["c1", "c7"]),
              build(:widget, id: "w2", component_ids: ["c2"]),
              build(:widget, id: "w3", component_ids: ["c5"]),
              build(:widget, id: "w4", component_ids: ["c1", "c2"]),
              build(:widget, id: "w5", component_ids: ["c6"])
            )

            expect {
              response1, response2, response3 = resolve_field("Component.widget", ["c1"], ["c2", "c5", "notfound"], ["c1"])

              expect(response1.map(&:id)).to contain_exactly("w1", "w4")
              expect(response2.map(&:id)).to contain_exactly("w2", "w3", "w4")
              expect(response3.map(&:id)).to contain_exactly("w1", "w4")
            }.to perform_datastore_search("main", 1).time

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.widget",
              "optimized_attempt_count" => 1,
              "degraded_to_separate_queries" => false,
              "id_set_count" => 2,
              "total_id_count" => 4
            })]
          end

          it "runs multiple filter value sets as separate queries if the query has aggregations or needs the total doc count" do
            index_into(
              graphql,
              build(:widget, id: "w1", component_ids: ["c1", "c7"], amount_cents: 100),
              build(:widget, id: "w2", component_ids: ["c2"], amount_cents: 200),
              build(:widget, id: "w3", component_ids: ["c1"], amount_cents: 300),
              build(:widget, id: "w4", component_ids: ["c1", "c9"], amount_cents: 400)
            )

            agg_query = aggregation_query_of(name: "agg", computations: [computation_of("amount_cents", :sum)])

            expect {
              response1, response2 = resolve_field(
                "Component.widget_aggregations",
                ["c1"], ["c2", "c5"],
                aggregations: {"agg" => agg_query}
              )

              expect(response1.aggregations).to eq({"agg:amount_cents:sum" => {"value" => 800.0}}) # 100 + 300 + 400
              expect(response2.aggregations).to eq({"agg:amount_cents:sum" => {"value" => 200.0}}) # just 200
            }.to perform_datastore_search("main", 2).times

            expect(logged_jsons_of_type(merged_queries_message_type)).to eq([])

            expect {
              response1, response2 = resolve_field("Component.widget", ["c1"], ["c2", "c5"], total_document_count_needed: true)

              expect(response1.total_document_count).to eq 3
              expect(response2.total_document_count).to eq 1
            }.to perform_datastore_search("main", 2).times

            expect(logged_jsons_of_type(merged_queries_message_type)).to eq([])
          end

          it "performs multiple queries as needed to when we get back incomplete results" do
            all_widgets = 1.upto(4).flat_map do |c|
              1.upto(10 * NestedRelationshipsSource::EXTRA_SIZE_MULTIPLIER).map do |w|
                build(:widget, id: "c#{c}_w#{w}", component_ids: ["c#{c}"], amount_cents: (100 * c) + w)
              end
            end
            index_into(graphql, *all_widgets)

            # If we request 5 results per id set, it takes an extra attempt:
            #   - Attempt 1 final size: (5 + 1) * id_sets.size * EXTRA_SIZE_MULTIPLIER = 6 * 4 * 4 = 96 results
            #     - We get back 40 results for `c1`, 40 results for `c2`, and 16 results for `c3`.
            #   - Attempt 2 final size: (5 + 1) * id_sets.size * EXTRA_SIZE_MULTIPLIER = 6 * 2 * 4 = 48 results
            #     - We get back 40 results for `c3` and 8 results for `c4`.
            expect {
              response1, response2, response3, response4 = resolve_field(
                "Component.widgets",
                ["c1"], ["c2"], ["c3"], ["c4"],
                sort: [{amount_cents: {"order" => "asc"}}],
                document_pagination: {first: 5} # note: we get back 1 extra result since it's needed for `has_next_page`
              )

              expect(response1.map(&:id)).to contain_exactly("c1_w1", "c1_w2", "c1_w3", "c1_w4", "c1_w5", "c1_w6")
              expect(response2.map(&:id)).to contain_exactly("c2_w1", "c2_w2", "c2_w3", "c2_w4", "c2_w5", "c2_w6")
              expect(response3.map(&:id)).to contain_exactly("c3_w1", "c3_w2", "c3_w3", "c3_w4", "c3_w5", "c3_w6")
              expect(response4.map(&:id)).to contain_exactly("c4_w1", "c4_w2", "c4_w3", "c4_w4", "c4_w5", "c4_w6")
            }.to perform_datastore_msearch("main", 2).times.and perform_datastore_search("main", 2).times

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.widgets",
              "optimized_attempt_count" => 2,
              "degraded_to_separate_queries" => false,
              "id_set_count" => 4,
              "total_id_count" => 4
            })]
            flush_logs

            # If we request 2 results per id set, it takes a full 3 optimized attempts:
            #   - Attempt 1 final size: (2 + 1) * id_sets.size * EXTRA_SIZE_MULTIPLIER = 3 * 4 * 4 = 48 results
            #     - We get back 48 results for `c1`, and 8 for `c2`.
            #   - Attempt 2 final size: (2 + 1) * id_sets.size * EXTRA_SIZE_MULTIPLIER = 3 * 2 * 4 = 24 results
            #     - We get back 24 results for `c3`.
            #   - Attempt 3 final size: (2 + 1) * id_sets.size * EXTRA_SIZE_MULTIPLIER = 3 * 1 * 4 = 12 results
            #     - We get back 12 results for `c3`.
            expect {
              response1, response2, response3, response4 = resolve_field(
                "Component.widgets",
                ["c1"], ["c2"], ["c3"], ["c4"],
                sort: [{amount_cents: {"order" => "asc"}}],
                document_pagination: {first: 2} # note: we get back 1 extra result since it's needed for `has_next_page`
              )

              expect(response1.map(&:id)).to contain_exactly("c1_w1", "c1_w2", "c1_w3")
              expect(response2.map(&:id)).to contain_exactly("c2_w1", "c2_w2", "c2_w3")
              expect(response3.map(&:id)).to contain_exactly("c3_w1", "c3_w2", "c3_w3")
              expect(response4.map(&:id)).to contain_exactly("c4_w1", "c4_w2", "c4_w3")
            }.to perform_datastore_msearch("main", 3).times.and perform_datastore_search("main", 3).times

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.widgets",
              "optimized_attempt_count" => 3,
              "degraded_to_separate_queries" => false,
              "id_set_count" => 4,
              "total_id_count" => 4
            })]
            flush_logs

            # If we request 2 results per id set with MAX_OPTIMIZED_ATTEMPTS reduced to 1, we fallback to separate queries after one attempt:
            #   - Attempt 1 final size: (2 + 1) * id_sets.size * EXTRA_SIZE_MULTIPLIER = 3 * 4 * 4 = 48 results
            #     - We get back 48 results for `c1`, and 8 for `c2`.
            #   - ...then we submit a single msearch request containing 2 queries (for c3 and c4).
            stub_const("#{NestedRelationshipsSource}::MAX_OPTIMIZED_ATTEMPTS", 1)
            expect {
              response1, response2, response3, response4 = resolve_field(
                "Component.widgets",
                ["c1"], ["c2"], ["c3"], ["c4"],
                sort: [{amount_cents: {"order" => "asc"}}],
                document_pagination: {first: 2} # note: we get back 1 extra result since it's needed for `has_next_page`
              )

              expect(response1.map(&:id)).to contain_exactly("c1_w1", "c1_w2", "c1_w3")
              expect(response2.map(&:id)).to contain_exactly("c2_w1", "c2_w2", "c2_w3")
              expect(response3.map(&:id)).to contain_exactly("c3_w1", "c3_w2", "c3_w3")
              expect(response4.map(&:id)).to contain_exactly("c4_w1", "c4_w2", "c4_w3")
            }.to perform_datastore_msearch("main", 2).times.and perform_datastore_search("main", 3).times

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.widgets",
              "optimized_attempt_count" => 1,
              "degraded_to_separate_queries" => true,
              "id_set_count" => 4,
              "total_id_count" => 4
            })]
          end

          it "respects any additional filters configured on the join" do
            index_into(
              graphql,
              build(:widget, id: "w1", component_ids: ["c1"], amount_cents: 100),
              build(:widget, id: "w2", component_ids: ["c1"], amount_cents: 200),
              build(:widget, id: "w3", component_ids: ["c2"], amount_cents: 300)
            )

            expect {
              response1, response2 = resolve_field("Component.dollar_widget", ["c1"], ["c2"])

              expect(response1.map(&:id)).to contain_exactly("w1")
              expect(response2.map(&:id)).to be_empty
            }.to perform_datastore_search("main", 1).time

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.dollar_widget",
              "optimized_attempt_count" => 1,
              "degraded_to_separate_queries" => false,
              "id_set_count" => 2,
              "total_id_count" => 2
            })]
          end
        end

        context "when `nested_relationship_resolver_mode` is set to `original`" do
          let(:graphql) { build_graphql(nested_relationship_resolver_mode: :original) }

          it "does not combine queries or log anything" do
            index_into(
              graphql,
              build(:widget, id: "w1", component_ids: ["c1", "c7"]),
              build(:widget, id: "w2", component_ids: ["c2"]),
              build(:widget, id: "w3", component_ids: ["c5"]),
              build(:widget, id: "w4", component_ids: ["c1", "c2"]),
              build(:widget, id: "w5", component_ids: ["c6"])
            )

            flush_logs

            expect {
              response1, response2, response3 = resolve_field("Component.widget", ["c1"], ["c2", "c5", "notfound"], ["c1"])

              expect(response1.map(&:id)).to contain_exactly("w1", "w4")
              expect(response2.map(&:id)).to contain_exactly("w2", "w3", "w4")
              expect(response3.map(&:id)).to contain_exactly("w1", "w4")
            }.to perform_datastore_search("main", 2).times.and perform_datastore_msearch("main", 1).time

            expect(logged_jsons).to be_empty
          end
        end

        context "when `nested_relationship_resolver_mode` is set to `comparison`" do
          let(:graphql) { build_graphql(nested_relationship_resolver_mode: :comparison) }
          let(:comparison_results_message_type) { "NestedRelationshipsComparisonResults" }

          it "performs the `:optimized` and `:original` logic and then compares and logs the results" do
            index_into(
              graphql,
              build(:widget, id: "w1", component_ids: ["c1", "c7"]),
              build(:widget, id: "w2", component_ids: ["c2"]),
              build(:widget, id: "w3", component_ids: ["c5"]),
              build(:widget, id: "w4", component_ids: ["c1", "c2"]),
              build(:widget, id: "w5", component_ids: ["c6"])
            )

            flush_logs

            expect {
              response1, response2, response3 = resolve_field("Component.widget", ["c1"], ["c2", "c5", "notfound"], ["c1"])

              expect(response1.map(&:id)).to contain_exactly("w1", "w4")
              expect(response2.map(&:id)).to contain_exactly("w2", "w3", "w4")
              expect(response3.map(&:id)).to contain_exactly("w1", "w4")
            }.to perform_datastore_search("main", 3).times.and perform_datastore_msearch("main", 2).time

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.widget",
              "optimized_attempt_count" => 1,
              "degraded_to_separate_queries" => false,
              "id_set_count" => 2,
              "total_id_count" => 4
            })]

            expect(logged_jsons_of_type(comparison_results_message_type)).to match [a_hash_including({
              "message_type" => comparison_results_message_type,
              "field" => "Component.widget",
              "optimized_faster" => (a_value == true).or(a_value == false),
              "got_same_results" => true,
              "id_set_count" => 2,
              "total_id_count" => 4
            })]

            flush_logs

            expect {
              response1 = resolve_field("Component.widget", ["c5"]).first

              expect(response1.map(&:id)).to contain_exactly("w3")
            }.to perform_datastore_search("main", 2).times.and perform_datastore_msearch("main", 2).time

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.widget",
              "optimized_attempt_count" => 1,
              "degraded_to_separate_queries" => false,
              "id_set_count" => 1,
              "total_id_count" => 1
            })]

            expect(logged_jsons_of_type(comparison_results_message_type)).to match [a_hash_including({
              "message_type" => comparison_results_message_type,
              "field" => "Component.widget",
              "optimized_faster" => (a_value == true).or(a_value == false),
              "got_same_results" => true,
              "id_set_count" => 1,
              "total_id_count" => 1
            })]
          end

          it "logs the document differences when there are any" do
            # Simulate a difference by modifying the optimized result we get.
            allow(QuerySource).to receive(:execute_one).and_wrap_original do |original, *args, **kwargs, &block|
              response = original.call(*args, **kwargs, &block)
              response.filter_results(["id"], response.documents.map(&:id).drop(1), 10)
            end

            index_into(
              graphql,
              build(:widget, id: "w1", component_ids: ["c1", "c7"]),
              build(:widget, id: "w2", component_ids: ["c2"]),
              build(:widget, id: "w3", component_ids: ["c5"]),
              build(:widget, id: "w4", component_ids: ["c1", "c2"]),
              build(:widget, id: "w5", component_ids: ["c6"])
            )

            flush_logs

            expect {
              response1, response2, response3 = resolve_field("Component.widget", ["c1"], ["c2", "c5", "notfound"], ["c1"])

              expect(response1.map(&:id)).to contain_exactly("w1", "w4")
              expect(response2.map(&:id)).to contain_exactly("w2", "w3", "w4")
              expect(response3.map(&:id)).to contain_exactly("w1", "w4")
            }.to perform_datastore_search("main", 3).times
              .and perform_datastore_msearch("main", 2).time
              .and log_warning(a_string_including(comparison_results_message_type))

            expect(logged_jsons_of_type(merged_queries_message_type)).to match [a_hash_including({
              "message_type" => merged_queries_message_type,
              "field" => "Component.widget",
              "optimized_attempt_count" => 1,
              "degraded_to_separate_queries" => false,
              "id_set_count" => 2,
              "total_id_count" => 4
            })]

            comparison_messages = logged_jsons_of_type(comparison_results_message_type)

            expect(comparison_messages).to match [a_hash_including({
              "message_type" => comparison_results_message_type,
              "field" => "Component.widget",
              "optimized_faster" => (a_value == true).or(a_value == false),
              "got_same_results" => false,
              "id_set_count" => 2,
              "total_id_count" => 4
            })]

            expect(comparison_messages.size).to eq 1

            expect(comparison_messages.dig(0, "original_documents")).to match [
              [a_string_including("w1 (hash:"), a_string_including("w4 (hash: ")],
              [a_string_including("w2 (hash:"), a_string_including("w3 (hash: "), a_string_including("w4 (hash: ")]
            ]

            expect(comparison_messages.dig(0, "optimized_documents")).to match [
              [a_string_including("w4 (hash: ")],
              [a_string_including("w2 (hash:"), a_string_including("w3 (hash: "), a_string_including("w4 (hash: ")]
            ]
          end

          it "uses the original logic for aggregations and `total_document_count_needed` queries, since they can't use the optimized logic" do
            index_into(
              graphql,
              build(:widget, id: "w1", component_ids: ["c1", "c7"], amount_cents: 100),
              build(:widget, id: "w2", component_ids: ["c2"], amount_cents: 200),
              build(:widget, id: "w3", component_ids: ["c1"], amount_cents: 300),
              build(:widget, id: "w4", component_ids: ["c1", "c9"], amount_cents: 400)
            )

            agg_query = aggregation_query_of(name: "agg", computations: [computation_of("amount_cents", :sum)])

            expect {
              response1, response2 = resolve_field(
                "Component.widget_aggregations",
                ["c1"], ["c2", "c5"],
                aggregations: {"agg" => agg_query}
              )

              expect(response1.aggregations).to eq({"agg:amount_cents:sum" => {"value" => 800.0}}) # 100 + 300 + 400
              expect(response2.aggregations).to eq({"agg:amount_cents:sum" => {"value" => 200.0}}) # just 200
            }.to perform_datastore_search("main", 2).times

            expect {
              response1, response2 = resolve_field("Component.widget", ["c1"], ["c2", "c5"], total_document_count_needed: true)

              expect(response1.total_document_count).to eq 3
              expect(response2.total_document_count).to eq 1
            }.to perform_datastore_search("main", 2).times

            expect(logged_jsons_of_type(merged_queries_message_type)).to eq([])
            expect(logged_jsons_of_type(comparison_results_message_type)).to eq([])
          end
        end

        def resolve_field(field, *value_sets, **query_args)
          graphql_field = graphql.schema.field_named(*field.split("."))
          join = graphql_field.relation_join
          monotonic_clock = graphql.monotonic_clock
          mode = graphql.config.nested_relationship_resolver_mode
          query = graphql.datastore_query_builder.new_query(
            search_index_definitions: graphql_field.type.unwrap_fully.search_index_definitions,
            # We need to request at least one field, or individual documents won't be requested.
            requested_fields: ["name"],
            **query_args
          )

          ::GraphQL::Dataloader.with_dataloading do |dataloader|
            context = ::GraphQL::Query::Context.new(
              query: instance_double(::GraphQL::Query),
              schema: graphql.schema.graphql_schema,
              values: {
                logger: graphql.logger,
                dataloader: dataloader,
                schema_element_names: graphql.runtime_metadata.schema_element_names,
                datastore_search_router: graphql.datastore_search_router,
                elastic_graph_query_tracker: QueryDetailsTracker.empty
              }
            )

            dataloader.with(NestedRelationshipsSource, query:, join:, context:, monotonic_clock:, mode:).load_all(value_sets.map(&:to_set))
          end
        end
      end
    end
  end
end
