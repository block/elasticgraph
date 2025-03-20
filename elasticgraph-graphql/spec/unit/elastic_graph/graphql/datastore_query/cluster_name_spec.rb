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
    RSpec.describe DatastoreQuery, "#cluster_name" do
      include_context "DatastoreQueryUnitSupport"

      let(:graphql) do
        build_graphql do |datastore_config|
          datastore_config.with(
            index_definitions: datastore_config.index_definitions.merge(
              "components" => config_index_def_of(query_cluster: "other1")
            )
          )
        end
      end

      let(:widgets_def) { graphql.datastore_core.index_definitions_by_name.fetch("widgets") }
      let(:addresses_def) { graphql.datastore_core.index_definitions_by_name.fetch("addresses") }
      let(:components_def) { graphql.datastore_core.index_definitions_by_name.fetch("components") }

      before do
        expect(widgets_def.cluster_to_query).to eq "main"
        expect(addresses_def.cluster_to_query).to eq "main"
        expect(components_def.cluster_to_query).to eq "other1"
      end

      it "returns the name of the datastore cluster from the search index definitions" do
        main_query = new_query(search_index_definitions: [widgets_def, addresses_def])
        expect(main_query.cluster_name).to eq "main"

        other_query = new_query(search_index_definitions: [components_def])
        expect(other_query.cluster_name).to eq "other1"
      end

      it "raises an error if the index definitions do not agree about the cluster" do
        query = new_query(search_index_definitions: [widgets_def, components_def])

        expect {
          query.cluster_name
        }.to raise_error Errors::ConfigError, a_string_including("main", "other1")
      end
    end
  end
end
