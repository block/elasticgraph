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
    RSpec.describe DatastoreQuery, "#requested_fields" do
      include_context "DatastoreQueryIntegrationSupport"

      specify "only the fields requested are returned by the datastore (including embedded object fields), ignoring unknown fields" do
        index_into(graphql, build(:widget))

        results = search_datastore(requested_fields: ["name", "id", "options.size", "foobar"])

        expect(results.first.payload.keys).to contain_exactly("name", "id", "options")
        expect(results.first["options"].keys).to contain_exactly("size")
      end

      specify "returns only id field in payload when no fields are requested (but still returns the right number of documents, provided `individual_docs_needed` is true)" do
        index_into(graphql, widget1 = build(:widget), widget2 = build(:widget))

        results = search_datastore(requested_fields: [], individual_docs_needed: true)

        expect(results.size).to eq 2 # 2 results should be returned to support `PageInfo` working correctly.
        expect(results.map(&:payload)).to contain_exactly(
          {"id" => widget1.fetch(:id)},
          {"id" => widget2.fetch(:id)}
        )
      end

      specify "returns no fields and no documents when no fields are requested (provided `individual_docs_needed` is not forced to true)" do
        index_into(graphql, build(:widget), build(:widget))

        results = search_datastore(requested_fields: [])

        expect(results.size).to eq 0
      end

      specify "returns all fields if passed `request_all_fields: true`" do
        index_into(graphql, build(:widget))

        results = search_datastore(request_all_fields: true)

        expect(results.first.payload.keys).to include("name", "id", "options", "the_opts", "tags")
        expect(results.first["options"].keys).to include("size", "the_sighs")
      end
    end
  end
end
