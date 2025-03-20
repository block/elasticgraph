# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/graphql/datastore_response/document"
require "json"

module ElasticGraph
  class GraphQL
    module DatastoreResponse
      RSpec.describe Document do
        let(:decoded_cursor_factory) { DecodedCursor::Factory.new(%w[amount_cents name]) }

        let(:raw_data) do
          {
            "_index" => "widgets",
            "_type" => "_doc",
            "_id" => "qwbfffaijhkljtfmcuwv",
            "_score" => 50.23,
            "_source" => {
              "id" => "qwbfffaijhkljtfmcuwv",
              "version" => 10,
              "amount_cents" => 300,
              "name" => "HuaweiP Smart",
              "created_at" => "2019-06-03T22 =>46 =>01Z",
              "options" => {
                "size" => "MEDIUM",
                "color" => "GREEN"
              },
              "component_ids" => []
            },
            "sort" => [
              300,
              "HuaweiP Smart"
            ]
          }
        end

        let(:document) { build_doc(raw_data) }

        it "exposes `raw_data`" do
          expect(document.raw_data).to eq raw_data
        end

        it "exposes `index_name`" do
          expect(document.index_name).to eq "widgets"
        end

        it "exposes `index_definition_name` (which is the same as the `index_name` on a non-rollover index)" do
          expect(document.index_definition_name).to eq "widgets"
        end

        it "exposes `index_definition_name` (which is the name of the parent index definition on a rollover index)" do
          document = build_doc(raw_data.merge("_index" => "components#{ROLLOVER_INDEX_INFIX_MARKER}2021-02"))
          expect(document.index_definition_name).to eq "components"
        end

        it "exposes `id`" do
          expect(document.id).to eq "qwbfffaijhkljtfmcuwv"
        end

        it "exposes `id` in payload even when there's no `_source` field" do
          raw_data = {
            "_index" => "widgets",
            "_type" => "_doc",
            "_id" => "qwbfffaijhkljtfmcuwv",
            "_score" => 50.23,
            "sort" => [
              300,
              "HuaweiP Smart"
            ]
          }
          document = build_doc(raw_data)
          expect(document.payload["id"]).to eq "qwbfffaijhkljtfmcuwv"
        end

        it "exposes `version`" do
          expect(document.version).to eq 10
        end

        it "returns `nil` if `version` field is missing" do
          document = build_doc(raw_data.merge("_source" => {}))
          expect(document.version).to eq nil
        end

        it "exposes `payload`" do
          expect(document.payload).to eq raw_data.fetch("_source")
        end

        it "exposes its datastore path" do
          expect(document.datastore_path).to eq "/widgets/_doc/qwbfffaijhkljtfmcuwv"
        end

        it "exposes a `cursor` encoded using the `DecodedCursor::Factory` passed to `build`" do
          expect(document.cursor).to eq decoded_cursor_factory.build(raw_data.fetch("sort"))
        end

        it "memoizes the `cursor`" do
          decoded_cursor_factory = instance_spy(DecodedCursor::Factory, build: "cursor")
          document = Document.build(raw_data, decoded_cursor_factory: decoded_cursor_factory)
          3.times { document.cursor }

          expect(decoded_cursor_factory).to have_received(:build).once
        end

        it "builds a valid cursor even if built without a cursor encoder" do
          document = Document.build(raw_data)
          expect(document.cursor).to be_a DecodedCursor
        end

        it "does not mutate the passed data" do
          expect {
            build_doc(raw_data)
          }.not_to change { JSON.generate(raw_data) }
        end

        it "inspects nicely" do
          expect(document.to_s).to eq "#<ElasticGraph::GraphQL::DatastoreResponse::Document /widgets/_doc/qwbfffaijhkljtfmcuwv>"
          expect(document.inspect).to eq document.to_s
        end

        it "allows fields to be accessed using `#[]` hash syntax" do
          expect(document["amount_cents"]).to eq 300
        end

        it "allows fields to be accessed using `#fetch` like on a hash" do
          expect(document.fetch("amount_cents")).to eq 300
          expect { document.fetch("foo") }.to raise_error(KeyError)
        end

        it "supports easy construction without the full raw data payload (such as for tests)" do
          doc = Document.with_payload({"foo" => 12})
          expect(doc.to_s).to eq "#<ElasticGraph::GraphQL::DatastoreResponse::Document /_doc/>"
          expect(doc["foo"]).to eq 12
        end

        def build_doc(data)
          Document.build(data, decoded_cursor_factory: decoded_cursor_factory)
        end
      end
    end
  end
end
