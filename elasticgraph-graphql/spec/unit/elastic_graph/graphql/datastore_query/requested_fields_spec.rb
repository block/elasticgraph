# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "#requested_fields" do
      include_context "DatastoreQueryUnitSupport"

      it "requests only non-id fields from the datastore when building the request body" do
        query = new_query(requested_fields: ["name", "id"])

        expect(datastore_body_of(query)[:_source][:includes]).to contain_exactly("name")
      end

      it "requests all fields in requested_fields when requested_fields does not include id" do
        query = new_query(requested_fields: ["name", "age"])

        expect(datastore_body_of(query)[:_source][:includes]).to contain_exactly("name", "age")
      end

      it "does not request _source when id is the only requested field" do
        query = new_query(requested_fields: ["id"])

        expect(datastore_body_of(query)[:_source]).to eq(false)
      end

      it "does not request _source when no fields are requested" do
        query = new_query(requested_fields: [])

        expect(datastore_body_of(query)[:_source]).to eq(false)
      end
    end
  end
end
