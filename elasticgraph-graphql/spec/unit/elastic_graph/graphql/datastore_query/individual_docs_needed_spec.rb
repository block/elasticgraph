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
    RSpec.describe DatastoreQuery, "#individual_docs_needed" do
      include_context "DatastoreQueryUnitSupport"

      it "defaults `individual_docs_needed` to `false` if there are no requested fields" do
        query = new_query(requested_fields: [])

        expect(query.individual_docs_needed).to be false
      end

      it "allows `individual_docs_needed` to be forced to `true` by the caller" do
        query = new_query(requested_fields: [], individual_docs_needed: true)
        expect(query.individual_docs_needed).to be true
      end

      it "forces `individual_docs_needed` to `true` if there are requested field, because we will not get back the requested fields if we do not fetch documents" do
        query = new_query(requested_fields: ["id"])
        expect(query.individual_docs_needed).to be true

        query = new_query(requested_fields: ["id"], individual_docs_needed: false)
        expect(query.individual_docs_needed).to be true
      end
    end
  end
end
