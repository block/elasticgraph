# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/elasticsearch/client"
require "elastic_graph/graphql/datastore_query"
require "elastic_graph/graphql/datastore_search_router"
require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/support/monotonic_clock"
require "support/sort"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreSearchRouter, :capture_logs do
      include SortSupport

      attr_accessor :schema_artifacts

      before(:context) do
        self.schema_artifacts = generate_schema_artifacts do |schema|
          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "currency", "String"
            t.field "name", "String"
            t.field "some_field", "String!"
            t.index "widgets"
          end
        end
      end

      let(:empty_response) do
        DatastoreResponse::SearchResponse::RAW_EMPTY.merge(
          "took" => 5, "_shards" => {"total" => 3, "successful" => 1, "skipped" => 0, "failed" => 0}, "status" => 200
        )
      end

      let(:main_datastore_client) { instance_spy(Elasticsearch::Client, cluster_name: "main") }
      let(:other_datastore_client) { instance_spy(Elasticsearch::Client, cluster_name: "other") }
      let(:graphql) { build_graphql }
      let(:router) { graphql.datastore_search_router }
      let(:datastore_query_builder) { graphql.datastore_query_builder }
      let(:now_when_msearch_is_called) { 100_000 }
      let(:monotonic_clock) { instance_double(Support::MonotonicClock, now_in_ms: now_when_msearch_is_called) }

      describe "#msearch" do
        before do
          allow(main_datastore_client).to receive(:msearch).and_return("took" => 10, "responses" => [
            empty_response.merge("r" => 1),
            empty_response.merge("r" => 2),
            empty_response.merge("r" => 3)
          ])
        end

        let(:sort_list) { [{"foo" => {"order" => "asc"}}] }
        let(:query1) { new_widgets_query(default_page_size: 10, individual_docs_needed: true) }
        let(:query2) { new_widgets_query(default_page_size: 3, individual_docs_needed: true) }

        it "passes a set of empty headers along with each search body to the datastore, since it requires that for msearch" do
          router.msearch([query1, query2])

          expect(main_datastore_client).to have_received(:msearch).with(a_hash_including(body: [
            {index: "widgets"},
            a_hash_including(sort: sort_list_with_missing_option_for(sort_list), size: a_value_within(1).of(10)),
            {index: "widgets"},
            a_hash_including(sort: sort_list_with_missing_option_for(sort_list), size: a_value_within(1).of(3))
          ]))
        end

        it "performs the request with a client-side timeout configured from the query deadlines" do
          router.msearch([query1.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + 117)])

          expect(main_datastore_client).to have_received(:msearch).with(a_hash_including(headers: {
            TIMEOUT_MS_HEADER => "117"
          }))
        end

        it "passes no timeout when no queries have a deadline" do
          expect(query1.monotonic_clock_deadline).to be nil
          expect(query2.monotonic_clock_deadline).to be nil

          router.msearch([query1, query2])
          expect(main_datastore_client).to have_received(:msearch).with(a_hash_including(headers: {}))
        end

        it "picks the numerical (not lexicographical) minimum timeout when multiple queries have a deadline" do
          router.msearch([
            query1.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + 117),
            query2.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + 9)
          ])

          expect(main_datastore_client).to have_received(:msearch).with(a_hash_including(headers: {
            TIMEOUT_MS_HEADER => "9"
          }))
        end

        it "ignores queries that have no `monotonic_clock_deadline` when picking the overall timeout" do
          router.msearch([
            query1.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + 117),
            query1.merge_with(monotonic_clock_deadline: nil),
            query2.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + 9)
          ])

          expect(main_datastore_client).to have_received(:msearch).with(a_hash_including(headers: {
            TIMEOUT_MS_HEADER => "9"
          }))
        end

        it "raises `Errors::RequestExceededDeadlineError` if a query has a deadline in the past" do
          queries = [
            query1.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + -3),
            query2.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + 9)
          ]

          expect {
            router.msearch(queries)
          }.to raise_error Errors::RequestExceededDeadlineError, /already \d+ ms past/
        end

        it "raises `Errors::RequestExceededDeadlineError` if a query has a deadline at the exact current monotonic clock time" do
          queries = [
            query1.merge_with(monotonic_clock_deadline: now_when_msearch_is_called),
            query2.merge_with(monotonic_clock_deadline: now_when_msearch_is_called + 9)
          ]

          expect {
            router.msearch(queries)
          }.to raise_error Errors::RequestExceededDeadlineError, /already \d+ ms past/
        end

        it "returns an `DatastoreResponse::SearchResponse` for each response from the datastore in a hash" do
          responses = router.msearch([query1, query2])

          expect(responses.values).to all be_a DatastoreResponse::SearchResponse
          expect(responses.keys).to eq [query1, query2]
          expect(responses.values.map(&:metadata)).to match [
            a_hash_including("r" => 1),
            a_hash_including("r" => 2)
          ]
        end

        it "raises `Errors::SearchFailedError` if a search fails for a transient reason" do
          allow(main_datastore_client).to receive(:msearch).and_return("took" => 10, "responses" => [
            empty_response,
            {"took" => 5, "error" => {"bad stuff" => "happened"}, "status" => 400}
          ])

          expect {
            router.msearch([query1, query2])
          }.to raise_error(Errors::SearchFailedError, a_string_including(
            "2) ", '{"index":"widgets"}', inspect_output_of('{"bad stuff" => "happened"}')
          ).and(excluding(
            # These are parts of the body of the request, which we don't want included because it could contain PII!.
            "track_total_hits", "size"
          )))
        end

        it "raises `::GraphQL::ExecutionError` if a search fails for a non-transient `too_many_buckets_exception` reason" do
          allow(main_datastore_client).to receive(:msearch).and_return("took" => 10, "responses" => [
            empty_response,
            {
              "status" => 400,
              "error" => {
                "root_cause" => [],
                "type" => "search_phase_execution_exception",
                "reason" => "",
                "grouped" => true,
                "caused_by" => {
                  "type" => "too_many_buckets_exception",
                  "reason" => "Trying to create too many buckets. Must be less than or equal to: [65535] but was [2056004]. This limit can be set by changing the [search.max_buckets] cluster level setting.",
                  "max_buckets" => 65535
                }
              }
            }
          ])

          expect {
            router.msearch([query1, query2])
          }.to raise_error ::GraphQL::ExecutionError, a_string_including(
            "Aggregation query produces too many groupings. Reduce the grouping cardinality to less than 65535 and try again."
          )
        end

        it "logs warning if a query has failed shards" do
          shard_failure_bits = {
            "_shards" => {
              "total" => 640,
              "successful" => 620,
              "skipped" => 0,
              "failed" => 20,
              "failures" => [
                {
                  "shard" => 15,
                  "index" => "widgets",
                  "node" => "uMUNaPy6TBa6j9fzRFpv0w",
                  "reason" => {
                    "type" => "illegal_argument_exception",
                    "reason" => "numHits must be > 0; TotalHitCountCollector can be used for the total hit count"
                  }
                }
              ]
            }
          }

          allow(main_datastore_client).to receive(:msearch).and_return("took" => 12, "responses" => [
            empty_response,
            empty_response.merge(shard_failure_bits)
          ])

          expect {
            router.msearch([query1, query2])
          }.to log(a_string_including(
            "The following queries have failed shards",
            "Query 2",
            "against index `widgets`",
            "illegal_argument_exception",
            "numHits must be > 0; TotalHitCountCollector can be used for the total hit count"
          ))
        end

        it "avoids the I/O cost of querying the datastore when given an empty list of queries" do
          results = router.msearch([])

          expect(results).to eq({})
          expect(main_datastore_client).not_to have_received(:msearch)
        end

        it "does not assume `Query.perform` yields all queries" do
          empty_query = new_widgets_query(requested_fields: [], total_document_count_needed: false)
          expect(empty_query).to be_empty

          results = router.msearch([query1, empty_query])
          expect(results.size).to eq(2)
        end

        it "records how long the queries took from the client and server's perspective" do
          allow(main_datastore_client).to receive(:msearch).and_return(
            {"took" => 47, "responses" => [empty_response.merge("r" => 1)]},
            {"took" => 12, "responses" => [empty_response.merge("r" => 2)]}
          )

          allow(monotonic_clock).to receive(:now_in_ms).and_return(100, 340, 500, 530)
          query_tracker = QueryDetailsTracker.empty

          expect {
            router.msearch([query1], query_tracker: query_tracker)
          }.to change { query_tracker.datastore_query_server_duration_ms }.from(0).to(47)
            .and change { query_tracker.datastore_query_client_duration_ms }.from(0).to(240)

          expect {
            router.msearch([query2], query_tracker: query_tracker)
          }.to change { query_tracker.datastore_query_server_duration_ms }.from(47).to(59)
            .and change { query_tracker.datastore_query_client_duration_ms }.from(240).to(270)
        end

        it "tolerates the datastore server response not indicating how long it took" do
          allow(main_datastore_client).to receive(:msearch).and_return("responses" => [
            empty_response.merge("r" => 1)
          ])

          query_tracker = QueryDetailsTracker.empty

          expect {
            router.msearch([query1], query_tracker: query_tracker)
          }.not_to change { query_tracker.datastore_query_server_duration_ms }.from(0)
        end

        it "prints via `puts` the datastore query and response only when `DEBUG_QUERY` is set" do
          formatted_messages_pattern = /QUERY:\n.*"index": "widgets".*\nRESPONSE:\n.*"responses"/m
          with_env("DEBUG_QUERY" => "1") do
            expect {
              router.msearch([query1, query2])
            }.to output(formatted_messages_pattern).to_stdout
          end

          with_env("DEBUG_QUERY" => nil) do
            expect {
              router.msearch([query1, query2])
            }.not_to output(formatted_messages_pattern).to_stdout
          end
        end

        def new_widgets_query(default_page_size: 50, **args)
          options = {
            search_index_definitions: [graphql.datastore_core.index_definitions_by_name.fetch("widgets")],
            sort: sort_list
          }.merge(args)

          datastore_query_builder.with(default_page_size: default_page_size).new_query(**options)
        end
      end

      def build_graphql
        super(clients_by_name: {"main" => main_datastore_client, "other" => other_datastore_client}, monotonic_clock: monotonic_clock, schema_artifacts: schema_artifacts)
      end
    end
  end
end
