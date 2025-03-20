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
    RSpec.describe DatastoreQuery, "#route_with_field_paths" do
      include_context "DatastoreQueryUnitSupport"

      let(:widgets_def) { graphql.datastore_core.index_definitions_by_name.fetch("widgets") }
      let(:addresses_def) { graphql.datastore_core.index_definitions_by_name.fetch("addresses") }
      let(:manufacturers_def) { graphql.datastore_core.index_definitions_by_name.fetch("manufacturers") }

      before do
        expect(widgets_def.route_with).to eq "workspace_id2"
        expect(addresses_def.route_with).to eq "id"
        expect(manufacturers_def.route_with).to eq "id"
      end

      it "returns a list of `route_with` values from the `search_index_definitions`" do
        query = new_query(search_index_definitions: [widgets_def, addresses_def])

        expect(query.route_with_field_paths).to contain_exactly("workspace_id2", "id")
      end

      it "deduplicates values when multiple search index definitions have the same `route_with` value" do
        query = new_query(search_index_definitions: [manufacturers_def, addresses_def])

        expect(query.route_with_field_paths).to contain_exactly("id")
      end
    end
  end
end
