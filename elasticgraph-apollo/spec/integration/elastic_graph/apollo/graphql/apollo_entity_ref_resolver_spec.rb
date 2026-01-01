# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/graphql/apollo_entity_ref_resolver"
require "elastic_graph/graphql"

module ElasticGraph
  module Apollo
    module GraphQL
      RSpec.describe ApolloEntityRefResolver, :uses_datastore, :factories, :builds_graphql, :builds_indexer do
        let(:graphql) { build_graphql(schema_artifacts_directory: "config/schema/artifacts_with_apollo") }
        let(:indexer) { build_indexer(datastore_core: graphql.datastore_core) }

        it "resolves an entity ref field backed by a non-list id field" do
          index_records(
            build(:component, id: "c1", owner_id: "oid_1"),
            build(:component, id: "c2", owner_id: nil)
          )

          data = execute_expecting_no_errors(<<~QUERY).dig("components", "nodes")
            query {
              components {
                nodes {
                  id
                  owner { token }
                }
              }
            }
          QUERY

          expect(data).to contain_exactly(
            {"id" => "c1", "owner" => {"token" => "oid_1"}},
            {"id" => "c2", "owner" => nil}
          )
        end

        it "resolves an entity ref field backed by a list of ids field" do
          index_records(
            build(:component, id: "c1", owner_ids: ["oid_1", "oid_2"]),
            build(:component, id: "c2", owner_ids: [])
          )

          data = execute_expecting_no_errors(<<~QUERY).dig("components", "nodes")
            query {
              components {
                nodes {
                  id
                  owners { token }
                }
              }
            }
          QUERY

          expect(data).to contain_exactly(
            {"id" => "c1", "owners" => [{"token" => "oid_1"}, {"token" => "oid_2"}]},
            {"id" => "c2", "owners" => []}
          )
        end

        it "resolves an entity ref field backed by a paginated list of ids field" do
          index_records(
            build(:component, id: "c1", owner_ids: ["oid_1", "oid_2", "oid_3", "oid_4"]),
            build(:component, id: "c2", owner_ids: [])
          )

          expected_end_cursor = "Mg"
          component_nodes_by_id = query_owners_paginated(first: 2)
          expect(component_nodes_by_id).to eq({
            "c1" => {
              "nodes" => [{"token" => "oid_1"}, {"token" => "oid_2"}],
              "page_info" => {"end_cursor" => expected_end_cursor, "has_next_page" => true},
              "total_edge_count" => 4
            },
            "c2" => {
              "nodes" => [],
              "page_info" => {"end_cursor" => nil, "has_next_page" => false},
              "total_edge_count" => 0
            }
          })

          component_nodes_by_id = query_owners_paginated(first: 2, after: expected_end_cursor)
          expect(component_nodes_by_id).to eq({
            "c1" => {
              "nodes" => [{"token" => "oid_3"}, {"token" => "oid_4"}],
              "page_info" => {"end_cursor" => "NA", "has_next_page" => false},
              "total_edge_count" => 4
            },
            "c2" => {
              "nodes" => [],
              "page_info" => {"end_cursor" => nil, "has_next_page" => false},
              "total_edge_count" => 0
            }
          })
        end

        def query_owners_paginated(**variables)
          execute_expecting_no_errors(<<~QUERY, variables: variables).dig("components", "nodes").to_h { |n| [n.fetch("id"), n.fetch("owners_paginated")] }
            query OwnersPaginated($first: Int, $after: Cursor) {
              components {
                nodes {
                  id
                  owners_paginated(first: $first, after: $after) {
                    total_edge_count
                    page_info {
                      has_next_page
                      end_cursor
                    }

                    nodes {
                      token
                    }
                  }
                }
              }
            }
          QUERY
        end

        def execute(query, **options)
          graphql.graphql_query_executor.execute(query, **options)
        end

        def execute_expecting_no_errors(query, **options)
          response = execute(query, **options)
          expect(response["errors"]).to be nil
          response.fetch("data")
        end
      end
    end
  end
end
