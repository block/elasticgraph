# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/graphql/engine_extension"
require "elastic_graph/apollo/graphql/entities_field_resolver"
require "elastic_graph/graphql"

module ElasticGraph
  module Apollo
    module GraphQL
      RSpec.describe EntitiesFieldResolver, :uses_datastore, :factories, :builds_graphql, :builds_indexer do
        let(:graphql) do
          build_graphql(
            schema_artifacts_directory: "config/schema/artifacts_with_apollo",
            extension_modules: [EngineExtension]
          )
        end

        let(:indexer) { build_indexer(datastore_core: graphql.datastore_core) }

        before do
          # Perform any cached calls to the datastore to happen before our `query_datastore`
          # matcher below which tries to assert which specific requests get made, since index definitions
          # have caching behavior that can make the presence or absence of that request slightly non-deterministic.
          pre_cache_index_state(graphql)
        end

        context "with an empty array of representations" do
          it "returns an empty array" do
            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: []) {
                  ... on Widget {
                    id
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [])

            # It should perform 0 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(0)
            # ...with 0 searches
            expect(performed_search_metadata("main")).to have_total_widget_searches(0)
          end
        end

        context "with a non-empty array of representations" do
          it "looks up each representation by the given fields, returning each in the response (or nil if not found)" do
            index_records(
              build(:widget, id: "w1", name: "widget1"),
              build(:widget, id: "w2", name: "widget2")
            )

            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", id: "w1"}
                  {__typename: "Widget", id: "w2"}
                  {__typename: "Widget", id: "w3"}
                  {__typename: "Widget", name: "widget1"}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "w1", "name" => "widget1"},
              {"id" => "w2", "name" => "widget2"},
              nil,
              {"id" => "w1", "name" => "widget1"}
            ])

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 2 searches (1 for the `id` queries, one for the `name`)
            expect(performed_search_metadata("main")).to have_total_widget_searches(2)
          end

          it "supports lookups on nested representation fields" do
            index_records(
              build(:widget, id: "w1", name: "widget1", options: build(:widget_options, size: "SMALL")),
              build(:widget, id: "w2", name: "widget2", options: build(:widget_options, size: "LARGE"))
            )

            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", options: {size: "SMALL"}}
                  {__typename: "Widget", options: {size: "MEDIUM"}}
                  {__typename: "Widget", options: {size: "LARGE"}}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "w1", "name" => "widget1"},
              nil,
              {"id" => "w2", "name" => "widget2"}
            ])

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 3 searches (1 for the `id` queries, one for the `name` and one for `options.size`)
            expect(performed_search_metadata("main")).to have_total_widget_searches(3)
          end

          it "resolves non-indexed entities, including a relation" do
            index_records(
              build(:team, id: "t1", current_name: "team1", country_code: "US"),
              build(:team, id: "t2", current_name: "team2", country_code: "MX"),
              build(:team, id: "t3", current_name: "team3", country_code: "US"),
              build(:team, id: "t4", current_name: "team4", country_code: "CA")
            )

            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Country", id: "US"},
                  {__typename: "Country", id: "MX"},
                  {__typename: "Country", id: "CA"}
                ]) {
                  ... on Country {
                    id
                    teams {
                      nodes {
                        current_name
                      }
                    }
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "US", "teams" => {"nodes" => [{"current_name" => "team1"}, {"current_name" => "team3"}]}},
              {"id" => "MX", "teams" => {"nodes" => [{"current_name" => "team2"}]}},
              {"id" => "CA", "teams" => {"nodes" => [{"current_name" => "team4"}]}}
            ])
          end

          it "returns empty values (nil or empty list) when asked to resolve non-relation/non-key fields on a non-indexed entity" do
            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Country", id: "US"},
                  {__typename: "Country", id: "MX"},
                  {__typename: "Country", id: "CA"}
                ]) {
                  ... on Country {
                    id
                    currency
                    # These two cases (nodes vs edges) have manifested different issues, so we check both here.
                    name_nodes: names { nodes }
                    name_edges: names { edges { node } }
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "US", "name_nodes" => {"nodes" => []}, "name_edges" => {"edges" => []}, "currency" => nil},
              {"id" => "MX", "name_nodes" => {"nodes" => []}, "name_edges" => {"edges" => []}, "currency" => nil},
              {"id" => "CA", "name_nodes" => {"nodes" => []}, "name_edges" => {"edges" => []}, "currency" => nil}
            ])
          end

          it "supports lookups involving fields that have an alternate `name_in_index`" do
            index_records(
              build(:widget, id: "w1", name: "widget1", the_options: build(:widget_options, the_size: "SMALL"))
            )

            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", id: "w1", the_options: {the_size: "SMALL"}}
                  {__typename: "Widget", name: "widget1", the_options: {the_size: "SMALL"}}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "w1", "name" => "widget1"},
              {"id" => "w1", "name" => "widget1"}
            ])

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 1 searches (1 for the `id` queries)
            expect(performed_search_metadata("main")).to have_total_widget_searches(2)
          end

          it "supports array and non-nullable fields" do
            index_records(
              build(:widget, id: "w1", name: "widget1", fees: [build(:money, currency: "USD", amount_cents: 100)])
            )

            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", id: "w1", fees: [{currency: "USD"}]}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "w1", "name" => "widget1"}
            ])

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 1 searches (1 for the `id` queries)
            expect(performed_search_metadata("main")).to have_total_widget_searches(1)
          end

          it "supports lookups on compound representation fields" do
            index_records(
              build(:widget, id: "w1", name: "foo", options: build(:widget_options, size: "SMALL")),
              build(:widget, id: "w2", name: "foo", options: build(:widget_options, size: "LARGE")),
              build(:widget, id: "w3", name: "bar", options: build(:widget_options, size: "LARGE"))
            )

            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", name: "foo", options: {size: "SMALL"}}
                  {__typename: "Widget", name: "bar", options: {size: "SMALL"}}
                  {__typename: "Widget", name: "foo", options: {size: "LARGE"}}
                  {__typename: "Widget", name: "bar", options: {size: "LARGE"}}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "w1", "name" => "foo"},
              nil,
              {"id" => "w2", "name" => "foo"},
              {"id" => "w3", "name" => "bar"}
            ])

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 4 searches
            expect(performed_search_metadata("main")).to have_total_widget_searches(4)
          end

          it "supports lookups on compound representation fields with id" do
            index_records(
              build(:widget, id: "w1", name: "foo", options: build(:widget_options, size: "SMALL")),
              build(:widget, id: "w2", name: "foo", options: build(:widget_options, size: "LARGE")),
              build(:widget, id: "w3", name: "bar", options: build(:widget_options, size: "LARGE"))
            )

            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", id: "w1", name: "foo", options: {size: "SMALL"}}
                  {__typename: "Widget", id: "w3", name: "bar", options: {size: "SMALL"}}
                  {__typename: "Widget", id: "w2", name: "foo", options: {size: "LARGE"}}
                  {__typename: "Widget", id: "w3", name: "bar", options: {size: "LARGE"}}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              {"id" => "w1", "name" => "foo"},
              nil,
              {"id" => "w2", "name" => "foo"},
              {"id" => "w3", "name" => "bar"}
            ])

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 1 searches (1 for the `id` queries)
            expect(performed_search_metadata("main")).to have_total_widget_searches(1)
          end

          it "ignores array filtering (for now, will be improved later)" do
            index_records(
              build(:widget, id: "w1", name: "foo", options: build(:widget_options, size: "SMALL")),
              build(:widget, id: "w2", name: "bar", options: build(:widget_options, size: "LARGE"))
            )

            response = execute(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", id: "w1", name: ["foo"]}
                  {__typename: "Widget", id: "w1", name: ["bar"]}
                  {__typename: "Widget", name: ["foo"], options: {size: "LARGE"}}
                  {__typename: "Widget", name: ["bar"], options: {size: "LARGE"}}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(response.dig("data", "_entities")).to eq [
              {"id" => "w1", "name" => "foo"},
              {"id" => "w1", "name" => "foo"},
              {"id" => "w2", "name" => "bar"},
              {"id" => "w2", "name" => "bar"}
            ]

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 2 searches (1 for the `id` queries, one for the `name`)
            expect(performed_search_metadata("main")).to have_total_widget_searches(2)
          end

          it "returns `nil` for representations with unexpected field types" do
            data = execute_expecting_no_errors(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", id: nil}
                  {__typename: "Widget", id: 3}
                  {__typename: "Widget", id: true}
                  {__typename: "Widget", id: []}
                  {__typename: "Widget", id: {}}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(data).to eq("_entities" => [
              nil,
              nil,
              nil,
              nil,
              nil
            ])

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 1 searches (1 for the `id` queries)
            expect(performed_search_metadata("main")).to have_total_widget_searches(1)
          end

          it "returns an error for each representation that is not a hash as expected, while still returning the entities that it can" do
            index_records(
              build(:widget, id: "w1", name: "widget1")
            )

            expect {
              response = execute(<<~QUERY)
                query {
                  _entities(representations: [
                    true
                    3
                    "foo"
                    {__typename: "Widget", id: "w1"}
                    2.5
                    [{__typename: "Widget", id: "w1"}]
                  ]) {
                    ... on Widget {
                      id
                      name
                    }
                  }
                }
              QUERY

              expect(response.dig("data", "_entities")).to eq [
                nil,
                nil,
                nil,
                {"id" => "w1", "name" => "widget1"},
                nil,
                nil
              ]

              expect(response["errors"]).to eq [
                {"message" => "Representation at index 0 is not a JSON object."},
                {"message" => "Representation at index 1 is not a JSON object."},
                {"message" => "Representation at index 2 is not a JSON object."},
                {"message" => "Representation at index 4 is not a JSON object."},
                {"message" => "Representation at index 5 is not a JSON object."}
              ]

              # It should perform 1 msearch request...
              expect(datastore_msearch_requests("main").size).to eq(1)
              # ...with 1 searches (1 for the `id` queries)
              expect(performed_search_metadata("main")).to have_total_widget_searches(1)
            }.to log_warning(a_string_including("is not a JSON object"))
          end

          it "returns an error if the representations lacks a `__typename`, while still returning the entities that it can" do
            index_records(
              build(:widget, id: "w1", name: "widget1")
            )

            expect {
              response = execute(<<~QUERY)
                query {
                  _entities(representations: [
                    {id: "w1"},
                    {__typename: "Widget", id: "w1"}
                  ]) {
                    ... on Widget {
                      id
                      name
                    }
                  }
                }
              QUERY

              expect(response.dig("data", "_entities")).to eq [
                nil,
                {"id" => "w1", "name" => "widget1"}
              ]

              expect(response["errors"]).to eq [
                {"message" => "Representation at index 0 lacks a `__typename`."}
              ]

              # It should perform 1 msearch request...
              expect(datastore_msearch_requests("main").size).to eq(1)
              # ...with 1 searches (1 for the `id` queries)
              expect(performed_search_metadata("main")).to have_total_widget_searches(1)
            }.to log_warning(a_string_including("lacks a `__typename`"))
          end

          it "returns an error if the `__typename` is unknown, while still returning the entities that it can" do
            index_records(
              build(:widget, id: "w1", name: "widget1")
            )

            expect {
              response = execute(<<~QUERY)
                query {
                  _entities(representations: [
                    {__typename: "Fidget", id: "w1"}
                    {__typename: "Widget", id: "w1"}
                  ]) {
                    ... on Widget {
                      id
                      name
                    }
                  }
                }
              QUERY

              expect(response.dig("data", "_entities")).to eq [
                nil,
                {"id" => "w1", "name" => "widget1"}
              ]

              expect(response["errors"]).to eq [
                {"message" => "Representation at index 0 has an unrecognized `__typename`: Fidget."}
              ]

              # It should perform 1 msearch request...
              expect(datastore_msearch_requests("main").size).to eq(1)
              # ...with 1 searches (1 for the `id` queries)
              expect(performed_search_metadata("main")).to have_total_widget_searches(1)
            }.to log_warning(a_string_including("has an unrecognized `__typename`: Fidget"))
          end

          it "returns an error if the only field in the representation is `__typename`, while still returning the entities that it can" do
            index_records(
              build(:widget, id: "w1", name: "widget1")
            )

            expect {
              response = execute(<<~QUERY)
                query {
                  _entities(representations: [
                    {__typename: "Widget"}
                    {__typename: "Widget", id: "w1"}
                  ]) {
                    ... on Widget {
                      id
                      name
                    }
                  }
                }
              QUERY

              expect(response.dig("data", "_entities")).to eq [
                nil,
                {"id" => "w1", "name" => "widget1"}
              ]

              expect(response["errors"]).to eq [
                {"message" => "Representation at index 0 has only a `__typename` field."}
              ]

              # It should perform 1 msearch request...
              expect(datastore_msearch_requests("main").size).to eq(1)
              # ...with 1 searches (1 for the `id` queries)
              expect(performed_search_metadata("main")).to have_total_widget_searches(1)
            }.to log_warning(a_string_including("has only a `__typename` field"))
          end
        end

        it "returns an error if a representation matches more than one document" do
          index_records(
            build(:widget, id: "w1", name: "foo"),
            build(:widget, id: "w2", name: "foo"),
            build(:widget, id: "w3", name: "bar")
          )

          expect {
            response = execute(<<~QUERY)
              query {
                _entities(representations: [
                  {__typename: "Widget", name: "foo"}
                  {__typename: "Widget", name: "bar"}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }
              }
            QUERY

            expect(response.dig("data", "_entities")).to eq [
              nil,
              {"id" => "w3", "name" => "bar"}
            ]

            expect(response["errors"]).to eq [
              {"message" => "Representation at index 0 matches more than one entity."}
            ]

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 2 searches (1 for the `id` queries, one for the `name`)
            expect(performed_search_metadata("main")).to have_total_widget_searches(2)
          }.to log_warning(a_string_including("matches more than one entity"))
        end

        it "does not interfere with other fields on the `Query` type, and batches datastore queries when possible" do
          expect {
            data = execute_expecting_no_errors(<<~EOS)
              query {
                _entities(representations: [
                  {__typename: "Widget", id: "w1"}
                ]) {
                  ... on Widget {
                    id
                    name
                  }
                }

                widgets {
                  total_edge_count
                }
              }
            EOS

            expect(data).to eq(
              "_entities" => [nil],
              "widgets" => {"total_edge_count" => 0}
            )

            # It should perform 1 msearch request...
            expect(datastore_msearch_requests("main").size).to eq(1)
            # ...with 2 searches (1 for the `id` queries, one for the `total_edge_count`)
            expect(performed_search_metadata("main")).to have_total_widget_searches(2)
          }.to query_datastore("main", 1).time
        end

        def execute(query, **options)
          response = nil

          expect {
            response = graphql.graphql_query_executor.execute(query, **options)
          }.to query_datastore("main", 1).time.or query_datastore("main", 0).times

          response
        end

        def execute_expecting_no_errors(query, **options)
          response = execute(query, **options)
          expect(response["errors"]).to be nil
          response.fetch("data")
        end

        def have_total_widget_searches(count)
          eq([{"index" => "widgets_rollover__*"}] * count)
        end
      end
    end
  end
end
