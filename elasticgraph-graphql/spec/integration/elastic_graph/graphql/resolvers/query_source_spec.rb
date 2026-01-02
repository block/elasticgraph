# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/query_details_tracker"
require "elastic_graph/graphql/resolvers/query_source"
require "graphql"

module ElasticGraph
  class GraphQL
    module Resolvers
      RSpec.describe QuerySource, :factories, :uses_datastore do
        let(:graphql) { build_graphql }

        it "batches up multiple queries, sending an msearch request containing them all to the datastore" do
          index_into(
            graphql,
            widget = build(:widget),
            component = build(:component)
          )

          widgets_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
          components_def = graphql.datastore_core.index_definitions_by_name.fetch("components")

          widget_query = graphql.datastore_query_builder.new_query(
            search_index_definitions: [widgets_def],
            requested_fields: ["id"]
          )

          component_query = graphql.datastore_query_builder.new_query(
            search_index_definitions: [components_def],
            requested_fields: ["id"]
          )

          # Perform any cached calls to the datastore to prevent them from alter interacting with the
          # `perform_datastore_msearch` assertion below.
          pre_cache_index_state(graphql)
          query_tracker = QueryDetailsTracker.empty

          expect {
            widget_results, component_results = ::GraphQL::Dataloader.with_dataloading do |dataloader|
              dataloader.with(QuerySource, graphql.datastore_search_router, query_tracker)
                .load_all([widget_query, component_query])
            end

            expect(widget_results.first.fetch("id")).to eq widget.fetch(:id)
            expect(component_results.first.fetch("id")).to eq component.fetch(:id)
          }.to perform_datastore_msearch(components_def.cluster_to_query, 1).time.and perform_datastore_search(components_def.cluster_to_query, 2).times
        end
      end
    end
  end
end
