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
          expect(response.raw_data).to eq raw_data
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

        it "exposes a `total_document_count` based on `hits.total`" do
          expect(response.total_document_count).to eq 17
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

            expect(response.raw_data).to eq({
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
