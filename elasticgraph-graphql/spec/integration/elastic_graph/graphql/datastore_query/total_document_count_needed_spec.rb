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
    RSpec.describe DatastoreQuery, "#total_document_count_needed" do
      include_context "DatastoreQueryIntegrationSupport"

      specify "returns doc count when it is requested" do
        index_into(graphql, build(:widget))

        results = search_datastore(total_document_count_needed: true)

        expect(results.total_document_count).to eq(1)
      end

      specify "raises an exception when total document count is not requested but accessed" do
        index_into(graphql, build(:widget))

        results = search_datastore(total_document_count_needed: false)

        expect {
          results.total_document_count
        }.to raise_error(Errors::CountUnavailableError)
      end
    end
  end
end
