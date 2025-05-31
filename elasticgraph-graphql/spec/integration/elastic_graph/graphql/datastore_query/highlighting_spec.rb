# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_integration_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "highlighting" do
      include_context "DatastoreQueryIntegrationSupport"

      it "returns `client_filters` highlights on the returned search hits when highlights are requested" do
        index_into(
          graphql,
          build(:widget, id: "w1", name: "Widget 1", tags: ["blue"]),
          build(:widget, id: "w2", name: "Widget 2", tags: ["blue"]),
          build(:widget, id: "w3", tags: ["red tag", "awesome", "orange-red"]),
          build(:widget, id: "w4", name: "Widget 4", tags: ["red tag", "awesome", "orange-red"])
        )

        results = search_datastore(
          request_all_highlights: true,
          client_filters: [{
            "any_of" => [
              {"name" => {"starts_with" => {"any_prefix_of" => ["Widget"]}}},
              {"tags" => {"any_satisfy" => {"contains" => {"any_substring_of" => ["red"]}}}}
            ]
          }]
        )

        expect(results.documents.to_h { |d| [d.id, d.highlights] }).to eq({
          "w1" => {"name" => ["<em>Widget 1</em>"]},
          "w2" => {"name" => ["<em>Widget 2</em>"]},
          "w3" => {"tags" => ["<em>red tag</em>", "<em>orange-red</em>"]},
          "w4" => {"name" => ["<em>Widget 4</em>"], "tags" => ["<em>red tag</em>", "<em>orange-red</em>"]}
        })

        results = search_datastore(
          requested_highlights: ["name"],
          client_filters: [{
            "any_of" => [
              {"name" => {"starts_with" => {"any_prefix_of" => ["Widget"]}}},
              {"tags" => {"any_satisfy" => {"contains" => {"any_substring_of" => ["red"]}}}}
            ]
          }]
        )

        expect(results.documents.to_h { |d| [d.id, d.highlights] }).to eq({
          "w1" => {"name" => ["<em>Widget 1</em>"]},
          "w2" => {"name" => ["<em>Widget 2</em>"]},
          "w3" => {},
          "w4" => {"name" => ["<em>Widget 4</em>"]}
        })

        results = search_datastore(
          request_all_highlights: true,
          requested_highlights: ["name"],
          client_filters: [{
            "any_of" => [
              {"name" => {"starts_with" => {"any_prefix_of" => ["Widget"]}}},
              {"tags" => {"any_satisfy" => {"contains" => {"any_substring_of" => ["red"]}}}}
            ]
          }]
        )

        expect(results.documents.to_h { |d| [d.id, d.highlights] }).to eq({
          "w1" => {"name" => ["<em>Widget 1</em>"]},
          "w2" => {"name" => ["<em>Widget 2</em>"]},
          "w3" => {"tags" => ["<em>red tag</em>", "<em>orange-red</em>"]},
          "w4" => {"name" => ["<em>Widget 4</em>"], "tags" => ["<em>red tag</em>", "<em>orange-red</em>"]}
        })

        results = search_datastore(
          request_all_highlights: true,
          client_filters: [{"name" => {"starts_with" => {"any_prefix_of" => ["Widget"]}}}],
          internal_filters: [{"tags" => {"any_satisfy" => {"contains" => {"any_substring_of" => ["red", "blue"]}}}}]
        )

        expect(results.documents.to_h { |d| [d.id, d.highlights] }).to eq({
          "w1" => {"name" => ["<em>Widget 1</em>"]},
          "w2" => {"name" => ["<em>Widget 2</em>"]},
          "w4" => {"name" => ["<em>Widget 4</em>"]}
        })

        results = search_datastore(
          request_all_highlights: true,
          internal_filters: [{
            "any_of" => [
              {"name" => {"starts_with" => {"any_prefix_of" => ["Widget"]}}},
              {"tags" => {"any_satisfy" => {"contains" => {"any_substring_of" => ["red"]}}}}
            ]
          }]
        )

        expect(results.documents.to_h { |d| [d.id, d.highlights] }).to eq({
          "w1" => {},
          "w2" => {},
          "w3" => {},
          "w4" => {}
        })

        results = search_datastore(
          request_all_highlights: false,
          client_filters: [{
            "any_of" => [
              {"name" => {"starts_with" => {"any_prefix_of" => ["Widget"]}}},
              {"tags" => {"any_satisfy" => {"contains" => {"any_substring_of" => ["red"]}}}}
            ]
          }]
        )

        expect(results.documents.to_h { |d| [d.id, d.highlights] }).to eq({
          "w1" => {},
          "w2" => {},
          "w3" => {},
          "w4" => {}
        })

        results = search_datastore(request_all_highlights: true)

        expect(results.documents.to_h { |d| [d.id, d.highlights] }).to eq({
          "w1" => {},
          "w2" => {},
          "w3" => {},
          "w4" => {}
        })
      end
    end
  end
end
