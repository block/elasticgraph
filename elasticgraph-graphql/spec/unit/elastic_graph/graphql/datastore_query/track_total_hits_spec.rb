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
    RSpec.describe DatastoreQuery, "#track_total_hits" do
      include_context "DatastoreQueryUnitSupport"

      it "sets `track_total_hits` to false when `total_document_count_needed = false`" do
        expect(datastore_body_of(new_query(total_document_count_needed: false))).to include(track_total_hits: false)
      end

      it "sets `track_total_hits` to true when `total_document_count_needed = true`" do
        expect(datastore_body_of(new_query(total_document_count_needed: true))).to include(track_total_hits: true)
      end
    end
  end
end
