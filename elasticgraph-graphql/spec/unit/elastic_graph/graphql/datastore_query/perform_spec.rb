# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"
require "support/aggregations_helpers"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, ".perform" do
      include AggregationsHelpers
      include_context "DatastoreQueryUnitSupport"

      let(:graphql) do
        build_graphql do |datastore_config|
          datastore_config.with(
            index_definitions: datastore_config.index_definitions.merge(
              "components" => config_index_def_of(query_cluster: "other1")
            )
          )
        end
      end

      let(:raw_doc) do
        {
          "_index" => "widgets",
          "_type" => "_doc",
          "_id" => "zwbfffaijhkljtfmcuwv",
          "_score" => nil,
          "_source" => {},
          "sort" => [300]
        }
      end

      specify "performs multiple queries, wrapping each response in an `DatastoreResponse::SearchResponse`" do
        widgets_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
        components_def = graphql.datastore_core.index_definitions_by_name.fetch("components")

        expect(widgets_def.cluster_to_query).to eq "main"
        expect(components_def.cluster_to_query).to eq "other1"

        query0 = new_query(search_index_definitions: [widgets_def], client_filters: [{"age" => {"equal_to_any_of" => [0]}}], requested_fields: ["name"])
        query1 = new_query(search_index_definitions: [widgets_def], client_filters: [{"age" => {"equal_to_any_of" => [10]}}], requested_fields: ["name"])
        query2 = new_query(search_index_definitions: [components_def], client_filters: [{"age" => {"equal_to_any_of" => [20]}}], requested_fields: ["name"])

        yielded_header_body_tuples_by_query = nil

        responses = DatastoreQuery.perform([query0, query1, query2]) do |header_body_tuples_by_query|
          yielded_header_body_tuples_by_query = header_body_tuples_by_query

          {
            query0 => raw_response_with_docs(raw_doc, raw_doc),
            query1 => raw_response_with_docs(raw_doc),
            query2 => raw_response_with_docs(raw_doc, raw_doc)
          }
        end

        expect(yielded_header_body_tuples_by_query).to match({
          query0 => [{index: "widgets_rollover__*"}, a_hash_including(query: {bool: {filter: [{terms: {"age" => [0]}}]}})],
          query1 => [{index: "widgets_rollover__*"}, a_hash_including(query: {bool: {filter: [{terms: {"age" => [10]}}]}})],
          query2 => [{index: "components"}, a_hash_including(query: {bool: {filter: [{terms: {"age" => [20]}}]}})]
        })

        expect(responses.values).to all be_a DatastoreResponse::SearchResponse
        expect(responses.size).to eq 3
        expect(responses.values.map(&:size)).to eq [2, 1, 2]
      end

      it "avoids yielding empty queries, providing a default empty search response to the caller" do
        filters = [{"name" => {"equal_to_any_of" => ["foo"]}}]
        empty_query = new_minimal_query(client_filters: filters)
        with_fields = new_minimal_query(client_filters: filters, requested_fields: ["name"])
        with_total_hits = new_minimal_query(client_filters: filters, total_document_count_needed: true)
        with_aggs = new_minimal_query(client_filters: filters, aggregations: [agg = aggregation_query_of(computations: [computation_of("amountMoney", "amount", :sum)])])
        with_all_highlights = new_minimal_query(client_filters: filters, request_all_highlights: true)
        with_requested_highlights = new_minimal_query(client_filters: filters, requested_highlights: ["name"])

        yielded_header_body_tuples_by_query = nil
        query_response = raw_response_with_docs(raw_doc)

        responses = DatastoreQuery.perform([
          empty_query,
          with_fields,
          with_total_hits,
          with_aggs,
          with_all_highlights,
          with_requested_highlights
        ]) do |header_body_tuples_by_query|
          yielded_header_body_tuples_by_query = header_body_tuples_by_query
          header_body_tuples_by_query.transform_values { query_response }
        end

        # Notably, `empty_query` shouldn't be yielded to the block...
        expect(yielded_header_body_tuples_by_query.keys).to contain_exactly(
          with_fields, with_total_hits,
          with_aggs.with(aggregations: {agg.name => agg}),
          with_all_highlights, with_requested_highlights
        )

        # ...but we should still get a response for it.
        expect(responses.transform_values { |response| response.size }).to eq(
          empty_query => 0,
          with_fields => 1,
          with_total_hits => 1,
          with_aggs => 1,
          with_all_highlights => 1,
          with_requested_highlights => 1
        )
      end

      it "raises an error if the logic has failed to return a response for a query" do
        widgets_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
        components_def = graphql.datastore_core.index_definitions_by_name.fetch("components")

        expect(widgets_def.cluster_to_query).to eq "main"
        expect(components_def.cluster_to_query).to eq "other1"

        query0 = new_query(search_index_definitions: [widgets_def], client_filters: [{"age" => {"equal_to_any_of" => [0]}}], requested_fields: ["name"])
        query1 = new_query(search_index_definitions: [widgets_def], client_filters: [{"age" => {"equal_to_any_of" => [10]}}], requested_fields: ["name"])
        query2 = new_query(search_index_definitions: [components_def], client_filters: [{"age" => {"equal_to_any_of" => [20]}}], requested_fields: ["name"])

        expect {
          DatastoreQuery.perform([query0, query1, query2]) do |header_body_tuples_by_query|
            {
              query0 => raw_response_with_docs(raw_doc, raw_doc),
              # Here we omit `query1` to simulate a response missing.
              # query1 => raw_response_with_docs(raw_doc),
              query2 => raw_response_with_docs(raw_doc, raw_doc)
            }
          end
        }.to raise_error Errors::SearchFailedError, a_string_including("does not have the expected set of queries", query1.inspect)
      end

      def new_minimal_query(requested_fields: [], total_document_count_needed: false, aggregations: [], **options)
        new_query(requested_fields: requested_fields, total_document_count_needed: total_document_count_needed, aggregations: aggregations, **options)
      end

      def raw_response_with_docs(*raw_docs)
        # deep copy RAW_EMPTY so our updates don't impact the original
        Marshal.load(Marshal.dump(DatastoreResponse::SearchResponse::RAW_EMPTY)).tap do |response|
          response["hits"]["hits"] = raw_docs
          response["hits"]["total"]["value"] = raw_docs.count
        end
      end
    end
  end
end
