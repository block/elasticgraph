# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "json"

module ElasticGraph
  class GraphQL
    module DatastoreResponse
      RSpec.describe SearchResponse do
        let(:decoded_cursor_factory) { DecodedCursor::Factory.new(["amount_cents"]) }
        let(:raw_data) do
          {
            "took" => 50,
            "timed_out" => false,
            "_shards" => {
              "total" => 5,
              "successful" => 5,
              "skipped" => 0,
              "failed" => 0
            },
            "hits" => {
              "total" => {
                "value" => 17,
                "relation" => "eq"
              },
              "max_score" => nil,
              "hits" => [
                {
                  "_index" => "widgets",
                  "_type" => "_doc",
                  "_id" => "qwbfffaijhkljtfmcuwv",
                  "_score" => nil,
                  "_source" => {
                    "id" => "qwbfffaijhkljtfmcuwv",
                    "version" => 10,
                    "amount_cents" => 300,
                    "name" => "HuaweiP Smart",
                    "created_at" => "2019-06-03T22:46:01Z",
                    "options" => {
                      "size" => "MEDIUM",
                      "color" => "GREEN"
                    },
                    "component_ids" => []
                  },
                  "sort" => [
                    300
                  ]
                },
                {
                  "_index" => "widgets",
                  "_type" => "_doc",
                  "_id" => "zwbfffaijhkljtfmcuwv",
                  "_score" => nil,
                  "_source" => {
                    "id" => "zwbfffaijhkljtfmcuwv",
                    "version" => 10,
                    "amount_cents" => 300,
                    "name" => "HuaweiP Smart",
                    "created_at" => "2019-06-03T22:46:01Z",
                    "options" => {
                      "size" => "MEDIUM",
                      "color" => "GREEN"
                    },
                    "component_ids" => []
                  },
                  "sort" => [
                    300
                  ]
                },
                {
                  "_index" => "widgets",
                  "_type" => "_doc",
                  "_id" => "dubsponikrrgasvwbthh",
                  "_score" => nil,
                  "_source" => {
                    "id" => "dubsponikrrgasvwbthh",
                    "version" => 7,
                    "amount_cents" => 200,
                    "name" => "Samsung Galaxy S9",
                    "created_at" => "2019-06-18T04:01:51Z",
                    "options" => {
                      "size" => "LARGE",
                      "color" => "BLUE"
                    },
                    "component_ids" => []
                  },
                  "sort" => [
                    200
                  ]
                }
              ]
            }
          }
        end

        let(:response) { build_response(raw_data) }

        it "builds from a raw datastore JSON response" do
          expect(response.documents.size).to eq 3
        end

        it "exposes `metadata` containing everything but the documents themselves" do
          expect(response.metadata).to eq(
            "took" => 50,
            "timed_out" => false,
            "_shards" => {
              "total" => 5,
              "successful" => 5,
              "skipped" => 0,
              "failed" => 0
            },
            "hits" => {
              "total" => {
                "value" => 17,
                "relation" => "eq"
              },
              "max_score" => nil
            }
          )
        end

        describe "#total_document_count" do
          it "returns the `hits.total` value" do
            expect(response.total_document_count).to eq 17
          end

          it "raises an error if it is unavailable because the query wasn't configured to request it" do
            response = build_response(Support::HashUtil.deep_merge(raw_data, {"hits" => {"total" => nil}}))

            expect {
              response.total_document_count
            }.to raise_error Errors::CountUnavailableError
          end

          it "allows the caller to provide a default which is used if the value is unavailable" do
            no_total_count_response = build_response(Support::HashUtil.deep_merge(raw_data, {"hits" => {"total" => nil}}))

            expect(no_total_count_response.total_document_count(default: 487)).to eq 487
            expect(response.total_document_count(default: 487)).to eq 17
          end
        end

        it "avoids mutating the raw data used to build the object" do
          expect {
            build_response(raw_data)
          }.not_to change { JSON.generate(raw_data) }
        end

        it "converts the documents to `DatastoreResponse::Document` objects" do
          expect(response.documents).to all be_a DatastoreResponse::Document
          expect(response.documents.map(&:id)).to eq %w[qwbfffaijhkljtfmcuwv zwbfffaijhkljtfmcuwv dubsponikrrgasvwbthh]
        end

        it "passes along the decoded cursor factory so that the documents can expose a cursor" do
          expect(response.documents.map { |doc| doc.cursor.encode }).to all match(/\w+/)
        end

        it "can be treated as a collection of documents" do
          expect(response.to_a).to eq response.documents
          expect(response.map(&:id)).to eq %w[qwbfffaijhkljtfmcuwv zwbfffaijhkljtfmcuwv dubsponikrrgasvwbthh]
          expect(response.size).to eq 3
          expect(response.empty?).to eq false
        end

        it "inspects nicely for when there are no documents" do
          response = build_response(raw_data_with_docs(0))

          expect(response.to_s).to eq "#<ElasticGraph::GraphQL::DatastoreResponse::SearchResponse size=0 []>"
          expect(response.inspect).to eq response.to_s
        end

        it "inspects nicely for when there is one document" do
          response = build_response(raw_data_with_docs(1))

          expect(response.to_s).to eq "#<ElasticGraph::GraphQL::DatastoreResponse::SearchResponse size=1 [" \
            "#<ElasticGraph::GraphQL::DatastoreResponse::Document /widgets/_doc/qwbfffaijhkljtfmcuwv>]>"
          expect(response.inspect).to eq response.to_s
        end

        it "inspects nicely for when there are two documents" do
          response = build_response(raw_data_with_docs(2))

          expect(response.to_s).to eq "#<ElasticGraph::GraphQL::DatastoreResponse::SearchResponse size=2 [" \
            "#<ElasticGraph::GraphQL::DatastoreResponse::Document /widgets/_doc/qwbfffaijhkljtfmcuwv>, " \
            "#<ElasticGraph::GraphQL::DatastoreResponse::Document /widgets/_doc/zwbfffaijhkljtfmcuwv>]>"
          expect(response.inspect).to eq response.to_s
        end

        it "inspects nicely for when there are 3 or more documents" do
          response = build_response(raw_data_with_docs(3))

          expect(response.to_s).to eq "#<ElasticGraph::GraphQL::DatastoreResponse::SearchResponse size=3 [" \
            "#<ElasticGraph::GraphQL::DatastoreResponse::Document /widgets/_doc/qwbfffaijhkljtfmcuwv>, " \
            "..., " \
            "#<ElasticGraph::GraphQL::DatastoreResponse::Document /widgets/_doc/dubsponikrrgasvwbthh>]>"
          expect(response.inspect).to eq response.to_s
        end

        it "exposes an empty response" do
          response = SearchResponse::EMPTY

          expect(response).to be_empty
          expect(response.to_a).to eq([])
          expect(response.metadata).to eq("hits" => {"total" => {"value" => 0}})
          expect(response.total_document_count).to eq 0
        end

        describe ".synthesize_from_ids" do
          it "creates a response matching the structure from the datastore using the given index and ids" do
            response = SearchResponse.synthesize_from_ids("widgets", %w[abc def ghi])

            expected_response = SearchResponse.build({
              "took" => 0,
              "timed_out" => false,
              "_shards" => {
                "total" => 0,
                "successful" => 0,
                "skipped" => 0,
                "failed" => 0
              },
              "hits" => {
                "total" => {
                  "value" => 3,
                  "relation" => "eq"
                },
                "max_score" => nil,
                "hits" => [
                  {
                    "_index" => "widgets",
                    "_type" => "_doc",
                    "_id" => "abc",
                    "_score" => nil,
                    "_source" => {"id" => "abc"},
                    "sort" => ["abc"]
                  },
                  {
                    "_index" => "widgets",
                    "_type" => "_doc",
                    "_id" => "def",
                    "_score" => nil,
                    "_source" => {"id" => "def"},
                    "sort" => ["def"]
                  },
                  {
                    "_index" => "widgets",
                    "_type" => "_doc",
                    "_id" => "ghi",
                    "_score" => nil,
                    "_source" => {"id" => "ghi"},
                    "sort" => ["ghi"]
                  }
                ]
              }
            })

            expect(response).to eq(expected_response)
          end
        end

        describe "#filter_results" do
          def response_of(*hits)
            build_response(Support::HashUtil.deep_merge(raw_data, {"hits" => {"hits" => hits}}))
          end

          it "returns the matching results" do
            response = response_of(
              bob = {"_id" => "B", "_source" => {"id" => "B", "name" => "Bob", "age" => 17}},
              {"_id" => "J", "_source" => {"id" => "J", "name" => "Judy", "age" => 43}},
              eileen = {"_id" => "E", "_source" => {"id" => "E", "name" => "Eileen", "age" => 12}}
            )

            filtered = response.filter_results("name", ["Bob", "Eileen"].to_set, 10)

            expect(filtered.documents.map(&:payload)).to eq [bob.fetch("_source"), eileen.fetch("_source")]
          end

          it "ignores values that do not match any results" do
            response = response_of(
              bob = {"_id" => "B", "_source" => {"id" => "B", "name" => "Bob", "age" => 17}},
              {"_id" => "J", "_source" => {"id" => "J", "name" => "Judy", "age" => 43}},
              {"_id" => "E", "_source" => {"id" => "E", "name" => "Eileen", "age" => 12}}
            )

            filtered = response.filter_results("name", ["Bob", "Hellen"].to_set, 10)

            expect(filtered.documents.map(&:payload)).to eq [bob.fetch("_source")]
          end

          it "raises an error if the given field isn't in `_source`" do
            response = response_of(
              {"_id" => "B", "_source" => {"id" => "B", "name" => "Bob", "age" => 17}},
              {"_id" => "J", "_source" => {"id" => "J", "name" => "Judy", "age" => 43}},
              {"_id" => "E", "_source" => {"id" => "E", "name" => "Eileen", "age" => 12}}
            )

            expect {
              response.filter_results("address", ["Bob", "Hellen"].to_set, 10)
            }.to raise_error a_string_including("address")
          end

          it "can filter on `id` without a value in `_source` since it can use `_id`, allowing us to avoid requesting `id` values" do
            response = response_of(
              {"_id" => "B"},
              {"_id" => "J"},
              {"_id" => "E"}
            )

            filtered = response.filter_results("id", ["B", "E", "F"].to_set, 10)

            expect(filtered.documents.map(&:id)).to eq ["B", "E"]
          end

          it "limits the returned results to the given size" do
            response = response_of(
              {"_id" => "B"},
              {"_id" => "J"},
              {"_id" => "E"},
              {"_id" => "G"},
              {"_id" => "F"}
            )

            filtered = response.filter_results("id", ["B", "E", "F"].to_set, 2)

            expect(filtered.documents.map(&:id)).to eq ["B", "E"]
          end

          it "returns an empty result when given no filter values" do
            response = response_of(
              {"_id" => "B", "_source" => {}},
              {"_id" => "J", "_source" => {}},
              {"_id" => "E", "_source" => {}}
            )

            filtered = response.filter_results("id", [].to_set, 10)

            expect(filtered).to be_empty
          end

          it "filters on the intersection of values when the named field is a list, to align with Elasticsearch/OpenSearch term filtering semantics" do
            response = response_of(
              match1 = {"_id" => "B", "_source" => {"id" => "B", "foo_ids" => [1, 17], "age" => 17}},
              {"_id" => "J", "_source" => {"id" => "J", "foo_ids" => [2, 20], "age" => 43}},
              match2 = {"_id" => "E", "_source" => {"id" => "E", "foo_ids" => [3, 19, 47], "age" => 12}}
            )

            filtered = response.filter_results("foo_ids", [1, 17, 19].to_set, 10)

            expect(filtered.documents.map(&:payload)).to eq [match1.fetch("_source"), match2.fetch("_source")]
          end

          it "can filter on a nested path" do
            response = response_of(
              bob = {"_id" => "B", "_source" => {"id" => "B", "info" => {"name" => "Bob"}, "age" => 17}},
              {"_id" => "J", "_source" => {"id" => "J", "info" => {"name" => "Judy"}, "age" => 43}},
              eileen = {"_id" => "E", "_source" => {"id" => "E", "info" => {"name" => "Eileen"}, "age" => 12}}
            )

            filtered = response.filter_results("info.name", ["Bob", "Eileen"].to_set, 10)

            expect(filtered.documents.map(&:payload)).to eq [bob.fetch("_source"), eileen.fetch("_source")]
          end

          it "preserves the `decoded_cursor_factory` that was on the original documents" do
            response = response_of(
              {"_id" => "B", "_source" => {"id" => "B", "name" => "Bob", "age" => 17}},
              {"_id" => "J", "_source" => {"id" => "J", "name" => "Judy", "age" => 43}},
              {"_id" => "E", "_source" => {"id" => "E", "name" => "Eileen", "age" => 12}}
            )
            expect(response.map(&:decoded_cursor_factory)).to eq([decoded_cursor_factory] * 3)

            filtered = response.filter_results("name", ["Bob", "Eileen"].to_set, 10)

            expect(filtered.map(&:decoded_cursor_factory)).to eq([decoded_cursor_factory] * 2)
          end

          it "preserves the response metadata that was on the original response" do
            metadata = {
              "took" => 50,
              "timed_out" => false,
              "_shards" => {"total" => 5, "successful" => 5, "skipped" => 0, "failed" => 0},
              "hits" => {"total" => nil}
            }
            response = build_response(metadata.merge({
              "hits" => {
                "hits" => [
                  {"_id" => "a", "_source" => {"id" => "a", "name" => "HuaweiP Smart"}},
                  {"_id" => "b", "_source" => {"id" => "b", "name" => "iPhone"}}
                ]
              }
            }))

            filtered = response.filter_results("id", ["b"].to_set, 10)

            expect(filtered.metadata).to eq metadata
          end

          it "clears the `total_document_count` because it cannot be provided accurately" do
            response = build_response({
              "hits" => {
                "total" => {
                  "value" => 17,
                  "relation" => "eq"
                },
                "hits" => [
                  {"_id" => "a", "_source" => {"id" => "a", "name" => "HuaweiP Smart"}},
                  {"_id" => "b", "_source" => {"id" => "b", "name" => "iPhone"}}
                ]
              }
            })
            expect(response.total_document_count).to eq 17

            filtered = response.filter_results("id", ["b"].to_set, 10)

            expect { filtered.total_document_count }.to raise_error Errors::CountUnavailableError
          end

          it "clears aggregations because it cannot be provided accurately" do
            response = build_response({
              "aggregations" => {},
              "hits" => {
                "total" => {
                  "value" => 17,
                  "relation" => "eq"
                },
                "hits" => [
                  {"_id" => "a", "_source" => {"id" => "a", "name" => "HuaweiP Smart"}},
                  {"_id" => "b", "_source" => {"id" => "b", "name" => "iPhone"}}
                ]
              }
            })
            expect(response.aggregations).to eq({})

            filtered = response.filter_results("id", ["b"].to_set, 10)

            expect { filtered.aggregations }.to raise_error Errors::AggregationsUnavailableError
          end
        end

        def raw_data_with_docs(count)
          documents = raw_data.fetch("hits").fetch("hits").first(count)
          raw_data.merge("hits" => raw_data.fetch("hits").merge("hits" => documents))
        end

        def build_response(data)
          SearchResponse.build(data, decoded_cursor_factory: decoded_cursor_factory)
        end
      end
    end
  end
end
