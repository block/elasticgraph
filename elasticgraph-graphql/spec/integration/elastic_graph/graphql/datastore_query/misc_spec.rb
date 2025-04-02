# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_integration_support"
require "elastic_graph/errors"
require "elastic_graph/graphql/datastore_search_router"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "misc" do
      include_context "DatastoreQueryIntegrationSupport"

      # This test must always run with VCR disabled, because it depends on sending
      # a real slow query and then timing out on the client side.
      describe "deadline behavior", :no_vcr do
        around do |ex|
          GC.disable # ensure GC pauses don't make the `search_datastore` call take longer
          ex.run
          GC.enable # re-enable GC.
        end

        before do
          # Prevent `list_indices_matching` datastore request from interacting with the timeout
          # test below, by pre-caching its results.
          pre_cache_index_state(graphql)
        end

        it "aborts a slow query on the basis of the deadline" do
          # To force a slow query, we update the body before submitting the search to have a slow script.
          # Note: 100K is the most loop iterations Elasticsearch allows:
          # https://github.com/elastic/elasticsearch/blob/v7.12.0/modules/lang-painless/src/main/java/org/elasticsearch/painless/CompilerSettings.java#L52-L57
          #
          # On my machine, this query takes 3-4 seconds. (But the timeout will make the test finish much faster!)
          intentionally_slow_client_class = ::Class.new(::SimpleDelegator) do
            def msearch(body:, **args, &block)
              body.last[:script_fields] = {
                slow: {
                  script: <<~EOS
                    String text = "";

                    for (int i = 0; i < 100000; i++) {
                      text += "abcdef";
                    }

                    return "done";
                  EOS
                }
              }

              super(body: body, **args, &block)
            end
          end

          client = intentionally_slow_client_class.new(main_datastore_client)
          graphql = build_graphql(clients_by_name: {"main" => client})

          index_into(graphql, build(:widget), build(:widget))

          expect {
            search_datastore(graphql: graphql) do |query|
              # Compute the deadline just before the query is executed, since the deadline is based on the
              # system monotonic clock and we want a very tight deadline. Since graphql dependencies
              # are loaded and initialized lazily, if we eagerly calculate the deadline before calling
              # `search_datastore`, the lazy initialization might cause us to have already passed our deadline
              # before the router is ready to submit the query to the datastore. That's a slightly different
              # case and code path than timing out while waiting on the datastore query, so we want to
              # guard against that here by delaying the computation of the deadline until the last possible
              # moment.
              query.with(monotonic_clock_deadline: graphql.monotonic_clock.now_in_ms + 200)
            end
          }.to raise_error(Errors::RequestExceededDeadlineError, a_string_including("request exceeded timeout"))
            # Really it should take ~50 ms, but give extra time for ruby VM overhead.
            # On CI we've seen it take 1000-1100 ms but never move than that. Meanwhile,
            # without the `monotonic_clock_deadline:` arg, the query takes 3-4 seconds, so
            # it taking under 1200 ms still demonstrates the query is being aborted early.
            .and take_less_than(1200).milliseconds
            .and log_warning(a_string_including("request exceeded timeout"))
        end
      end

      context "when the indexed type has nested `default_sort_fields`" do
        let(:graphql) do
          build_graphql(schema_definition: lambda do |schema|
            schema.object_type "Money" do |t|
              t.field "currency", "String!"
              t.field "amount_cents", "Int!"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime"
              t.field "workspace_id", "ID", name_in_index: "workspace_id2"
              t.field "cost", "Money"

              t.index "widgets" do |i|
                i.rollover :yearly, "created_at"
                i.route_with "workspace_id"
                i.default_sort "cost.amount_cents", :desc
              end
            end
          end)
        end

        it "correctly sorts on that nested field" do
          index_into(
            graphql,
            widget1 = build(:widget, cost: {currency: "USD", amount_cents: 100}),
            widget2 = build(:widget, cost: {currency: "USD", amount_cents: 300}),
            widget3 = build(:widget, cost: {currency: "USD", amount_cents: 200})
          )

          expect(ids_of(search_datastore.to_a)).to eq(ids_of([widget2, widget3, widget1]))
        end
      end

      context "when indices have not yet been configured", :builds_admin do
        let(:graphql) do
          build_graphql(schema_definition: lambda do |schema|
            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime!"
              t.index unique_index_name do |i|
                i.rollover :monthly, "created_at"
              end
            end
          end)
        end

        it "raises a `GraphQL::ExecutionError` indicating they need to be configured" do
          widgets_def = graphql.datastore_core.index_definitions_by_name.fetch(unique_index_name)

          query = graphql.datastore_query_builder.new_query(
            search_index_definitions: [widgets_def],
            requested_fields: ["id"]
          )

          index_names = main_datastore_client.list_indices_matching("*")
          expect(index_names).not_to include(a_string_including(unique_index_name))

          expect { perform_query(graphql, query) }.to raise_error ::GraphQL::ExecutionError, DatastoreSearchRouter::INDICES_NOT_CONFIGURED_MESSAGE

          admin = build_admin(datastore_core: graphql.datastore_core)
          admin.cluster_configurator.configure_cluster(StringIO.new)

          # ...but after configuring them, the error goes away (even though no documents have been indexed!)
          results = perform_query(graphql, query)
          expect(results.to_a).to eq []
        end
      end
    end
  end
end
