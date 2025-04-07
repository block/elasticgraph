# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--search" do
    include_context "ElasticGraph GraphQL acceptance support"

    with_both_casing_forms do
      it "indexes and queries (with filter support) records", :expect_search_routing, :expect_index_exclusions do
        # Index widgets created at different months so that they go to different rollover indices, e.g. widgets_rollover__2019-06 and widgets_rollover__2019-07
        index_records(
          widget1 = build(
            :widget,
            workspace_id: "workspace_1",
            amount_cents: 100,
            options: build(:widget_options, size: "SMALL", color: "BLUE"),
            cost_currency: "USD",
            name: "thing1",
            created_at: "2019-06-02T06:00:00.000Z",
            created_at_time_of_day: "06:00:00",
            tags: ["abc", "def"],
            fees: [{currency: "USD", amount_cents: 15}, {currency: "CAD", amount_cents: 30}]
          ),
          widget2 = build(
            :widget,
            workspace_id: "ignored_workspace_2",
            amount_cents: 200,
            options: build(:widget_options, size: "SMALL", color: "RED"),
            cost_currency: "USD",
            name: "thing2",
            created_at: "2019-07-02T12:00:00.000Z",
            created_at_time_of_day: "12:00:00.1",
            tags: ["ghi", "jkl"],
            fees: [{currency: "USD", amount_cents: 25}, {currency: "CAD", amount_cents: 40}]
          ),
          widget3 = build(
            :widget,
            workspace_id: "workspace_3",
            amount_cents: 300,
            cost_currency: "USD",
            name: nil, # expected to be nil by some queries below
            options: build(:widget_options, size: "MEDIUM", color: "RED"),
            created_at: "2019-08-02T18:00:00.000Z",
            created_at_time_of_day: "18:00:00.123",
            tags: ["mno", "pqr"],
            fees: [{currency: "USD", amount_cents: 35}, {currency: "CAD", amount_cents: 50}]
          )
        )

        unfiltered_widget_currencies = list_widget_currencies
        expect(unfiltered_widget_currencies).to match([{
          "id" => "USD",
          case_correctly("widget_names") => {
            case_correctly("page_info") => {
              case_correctly("end_cursor") => /\w+/,
              case_correctly("start_cursor") => /\w+/,
              case_correctly("has_next_page") => false,
              case_correctly("has_previous_page") => false
            },
            case_correctly("total_edge_count") => 2,
            "edges" => [
              {"node" => "thing1", "cursor" => /\w+/},
              {"node" => "thing2", "cursor" => /\w+/}
            ]
          },
          case_correctly("widget_options") => {
            "colors" => [enum_value("BLUE"), enum_value("RED")],
            "sizes" => [enum_value("MEDIUM"), enum_value("SMALL")]
          },
          case_correctly("widget_tags") => ["abc", "def", "ghi", "jkl", "mno", "pqr"],
          case_correctly("widget_fee_currencies") => ["CAD", "USD"]
        }])

        expect(list_widget_currencies(filter: {id: {equal_to_any_of: ["USD"]}})).to eq(unfiltered_widget_currencies)
        expect_to_have_routed_to_shards_with("main", ["widget_currencies_rollover__*", nil])

        expect(list_widget_currencies(filter: {primary_continent: {equal_to_any_of: ["North America"]}})).to eq(unfiltered_widget_currencies)
        expect_to_have_routed_to_shards_with("main", ["widget_currencies_rollover__*", "North America"])

        options_any_of_filter = [
          {size: {equal_to_any_of: [enum_value(:MEDIUM)]}},
          {
            size: {equal_to_any_of: [enum_value(:SMALL)]},
            color: {equal_to_any_of: [enum_value(:BLUE)]}
          }
        ]
        widgets = list_widgets_with(<<~EOS, order_by: [:amount_cents_ASC], filter: {options: {any_of: options_any_of_filter}})
          #{case_correctly("amount_cents")}
          tags
          fees {
            currency
            #{case_correctly("amount_cents")}
          }
        EOS

        expect(widgets).to match([
          string_hash_of(widget1, :id, :amount_cents, :tags, :fees),
          string_hash_of(widget3, :id, :amount_cents, :tags, :fees)
        ])

        widgets = list_widgets_with(<<~EOS, order_by: [:amount_cents_ASC], filter: {options: {not: {not: {any_of: options_any_of_filter}}}})
          #{case_correctly("amount_cents")}
          tags
          fees {
            currency
            #{case_correctly("amount_cents")}
          }
        EOS

        expect(widgets).to match([
          string_hash_of(widget1, :id, :amount_cents, :tags, :fees),
          string_hash_of(widget3, :id, :amount_cents, :tags, :fees)
        ])

        widgets = list_widgets_with(:amount_cents,
          filter: {id: {equal_to_any_of: [widget1.fetch(:id), widget2.fetch(:id), "", " ", "\n"]}}, # empty strings should be ignored.
          order_by: [:amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget1, :id, :amount_cents),
          string_hash_of(widget2, :id, :amount_cents)
        ])

        widgets = list_widgets_with(:amount_cents,
          filter: {amount_cents: {gt: 150}},
          order_by: [:amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Verify that we can fetch, filter and sort by a graphql-only field which is an alias for a child field.
        # (`Widget.size` is an alias for the indexed `Widget.options.size` field).
        widgets = list_widgets_with(:size, order_by: [:size_DESC, :amount_cents_ASC])
        expect(widgets).to match([
          {"id" => widget1.fetch(:id), "size" => enum_value("SMALL")},
          {"id" => widget2.fetch(:id), "size" => enum_value("SMALL")},
          {"id" => widget3.fetch(:id), "size" => enum_value("MEDIUM")}
        ])
        widgets = list_widgets_with(:size, order_by: [:size_ASC, :amount_cents_ASC])
        expect(widgets).to match([
          {"id" => widget3.fetch(:id), "size" => enum_value("MEDIUM")},
          {"id" => widget1.fetch(:id), "size" => enum_value("SMALL")},
          {"id" => widget2.fetch(:id), "size" => enum_value("SMALL")}
        ])
        widgets = list_widgets_with(:size, filter: {size: {equal_to_any_of: [enum_value(:MEDIUM)]}})
        expect(widgets).to match([{"id" => widget3.fetch(:id), "size" => enum_value("MEDIUM")}])

        # Verify that we can order by a nullable field and paginate over it.
        widgets, page_info = list_widgets_and_page_info_with(:name, order_by: [:name_ASC], first: 1)
        expect(widgets).to match([{"id" => widget3.fetch(:id), "name" => nil}]) # nil sorts first
        widgets, page_info = list_widgets_and_page_info_with(:name, order_by: [:name_ASC], first: 1, after: page_info.dig(case_correctly("end_cursor")))
        expect(widgets).to match([string_hash_of(widget1, :id, :name)])
        widgets, page_info = list_widgets_and_page_info_with(:name, order_by: [:name_ASC], first: 1, after: page_info.dig(case_correctly("end_cursor")))
        expect(widgets).to match([string_hash_of(widget2, :id, :name)])
        expect(page_info).to include(case_correctly("has_next_page") => false)

        # Verify we can use the `not` filter operator correctly
        widgets = list_widgets_with(:amount_cents,
          filter: {options: {not: {color: {equal_to_any_of: [enum_value(:BLUE)]}}}},
          order_by: [:amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Verify we can use the `not` filter operator correctly
        widgets = list_widgets_with(:amount_cents,
          filter: {options: {not: {not: {color: {equal_to_any_of: [enum_value(:BLUE)]}}}}},
          order_by: [:amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget1, :id, :amount_cents)
        ])

        widgets = list_widgets_with(:amount_cents,
          filter: {options: {not: {color: {equal_to_any_of: [nil]}}}},
          order_by: [:amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget1, :id, :amount_cents),
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        widgets = list_widgets_with(:amount_cents,
          filter: {not: {amount_cents: {gt: 150}}},
          order_by: [:amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget1, :id, :amount_cents)
        ])

        # Verify that we can filter on `DateTime` fields (and that `nil` DateTime filter values are treated as `true`)
        widgets = list_widgets_with(:created_at,
          filter: {created_at: {gte: "2019-07-02T12:00:00Z", lt: nil}},
          order_by: [:created_at_ASC])
        expect_to_have_excluded_indices("main", [index_definition_name_for("widgets_rollover__before_2019")])

        expect(widgets).to match([
          string_hash_of(widget2, :id, :created_at),
          string_hash_of(widget3, :id, :created_at)
        ])

        # Verify the boundaries of `DateTime` field filtering.
        widgets = list_widgets_with(:created_at,
          filter: {created_at: {gte: "0001-01-01T00:00:00Z", lt: "9999-12-31T23:59:59.999Z"}},
          order_by: [:created_at_ASC])

        expect(widgets).to match([
          string_hash_of(widget1, :id, :created_at),
          string_hash_of(widget2, :id, :created_at),
          string_hash_of(widget3, :id, :created_at)
        ])

        expected_msg = "DateTime: must be formatted as an ISO8601 DateTime string with a 4 digit year"
        expect {
          error = query_widgets_with(:created_at,
            filter: {created_at: {lt: "10000-01-01T00:00:00Z"}},
            allow_errors: true).dig("errors", 0, "message")
          expect(error).to include(expected_msg)
        }.to log_warning(a_string_including(expected_msg))

        # Verify that we can filter on `DateTime` time-of-day
        widgets = list_widgets_with(:created_at,
          filter: {created_at: {time_of_day: {gte: "02:00:00", lt: "13:00:00", time_zone: "America/Los_Angeles"}}},
          order_by: [:created_at_ASC])
        expect(widgets).to match([
          string_hash_of(widget2, :id, created_at: "2019-07-02T12:00:00.000Z"), # 2 am Pacific
          string_hash_of(widget3, :id, created_at: "2019-08-02T18:00:00.000Z") # 10 am pacific
        ])

        # Demonstrate that `time_of_day.time_zone` defaults to UTC when not provided.
        widgets = list_widgets_with(:created_at,
          filter: {created_at: {time_of_day: {gte: "02:00:00", lt: "13:00:00"}}},
          order_by: [:created_at_ASC])
        expect(widgets).to match([
          string_hash_of(widget1, :id, created_at: "2019-06-02T06:00:00.000Z"),
          string_hash_of(widget2, :id, created_at: "2019-07-02T12:00:00.000Z")
        ])

        # Verify that we can filter on `Date` fields (and that `nil` Date filter values are treated as `true`)
        widgets = list_widgets_with(:created_on,
          filter: {created_on: {lte: "2019-07-02", gte: nil}},
          order_by: [:created_on_ASC])

        expect(widgets).to match([
          string_hash_of(widget1, :id, :created_on),
          string_hash_of(widget2, :id, :created_on)
        ])

        # Verify that a datetime filter that excludes all possible records returns nothing (and avoids
        # querying the datastore entirely, since it is not needed).
        expect {
          widgets = list_widgets_with(:created_at,
            # Make an empty time set with our `created_at` filter that can't match any widgets.
            filter: {created_at: {gte: "2019-07-02T12:00:00Z", lt: "2019-07-02T12:00:00Z"}},
            order_by: [:created_at_ASC])
          expect(widgets).to eq []
        }.to make_no_datastore_calls("main")

        # Verify that a filter on the shard routing field that excludes all possible values returns
        # nothing (and avoids querying the datastore entirely, since it is not needed).
        expect {
          widgets = list_widgets_with(:created_at,
            filter: {workspace_id: {equal_to_any_of: []}},
            order_by: [:created_at_ASC])
          expect(widgets).to eq []
        }.to make_no_datastore_calls("main")

        # Verify that we can filter on `LocalTime` fields
        widgets = list_widgets_with(:created_at_time_of_day,
          filter: {created_at_time_of_day: {gte: "10:00:00"}},
          order_by: [:created_at_time_of_day_ASC])
        expect(widgets).to match([
          string_hash_of(widget2, :id, :created_at_time_of_day),
          string_hash_of(widget3, :id, :created_at_time_of_day)
        ])

        widgets = list_widgets_with(:created_at_time_of_day,
          filter: {created_at_time_of_day: {gt: "05:00:00", lt: "15:00:00"}},
          order_by: [:created_at_time_of_day_ASC])
        expect(widgets).to match([
          string_hash_of(widget1, :id, :created_at_time_of_day),
          string_hash_of(widget2, :id, :created_at_time_of_day)
        ])

        # Demonstrate that filter field name translation works (`amount_cents2`
        # is a GraphQL alias for the `amount_cents` field in the index).
        widgets = list_widgets_with(:amount_cents2,
          filter: {amount_cents2: {gt: 150}},
          order_by: [:amount_cents2_ASC])

        expect(widgets).to match([
          string_hash_of(widget2, :id, amount_cents2: widget2.fetch(case_correctly("amount_cents").to_sym)),
          string_hash_of(widget3, :id, amount_cents2: widget3.fetch(case_correctly("amount_cents").to_sym))
        ])

        widgets = list_widgets_with(:amount_cents, order_by: [:cost_amount_cents_DESC])

        expect(widgets).to match([
          string_hash_of(widget3, :id, :amount_cents),
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget1, :id, :amount_cents)
        ])

        # Test `equal_to_any_of` with only `[nil]`
        widgets = list_widgets_with(:amount_cents,
          filter: {name: {equal_to_any_of: [nil]}})

        expect(widgets).to match([
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Test `equal_to_any_of` with only `[nil]` in an `any_of`
        widgets = list_widgets_with(:amount_cents,
          filter: {any_of: [name: {equal_to_any_of: [nil]}]})

        expect(widgets).to match([
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Test `not: {any_of: []}` results in all matching documents
        widgets = list_widgets_with(:amount_cents,
          filter: {not: {any_of: []}})

        expect(widgets).to match([
          string_hash_of(widget3, :id, :amount_cents),
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget1, :id, :amount_cents)
        ])

        # Test `not: {not: {any_of: []}}` results in no matching documents
        widgets = list_widgets_with(:amount_cents,
          filter: {not: {not: {any_of: []}}})

        expect(widgets).to match([])

        # Test `not: {any_of: [emptyPredicate]}` results in no matching documents
        widgets = list_widgets_with(:amount_cents,
          filter: {not: {any_of: [{name: {equal_to_any_of: nil}}]}})

        expect(widgets).to eq []

        # Test `not: {any_of: [emptyPredicate, nonEmptyPredicate]}` results in no matching documents
        widgets = list_widgets_with(:amount_cents,
          filter: {not: {any_of: [{name: {equal_to_any_of: nil}}, {amount_cents: {gt: 150}}]}})

        expect(widgets).to eq []

        # Test `equal_to_any_of` with `[nil, other_value]`
        widgets = list_widgets_with(:amount_cents,
          filter: {name: {equal_to_any_of: [nil, "thing2", "", " ", "\n"]}}, # empty strings should be ignored.,
          order_by: [:amount_cents_DESC])

        expect(widgets).to match([
          string_hash_of(widget3, :id, :amount_cents),
          string_hash_of(widget2, :id, :amount_cents)
        ])

        # Test `not` with `equal_to_any_of` with only `[nil]`
        widgets = list_widgets_with(:amount_cents,
          filter: {not: {name: {equal_to_any_of: [nil]}}},
          order_by: [:amount_cents_DESC])

        expect(widgets).to match([
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget1, :id, :amount_cents)
        ])

        # Test `not` with `equal_to_any_of` with `[nil, other_value]`
        widgets = list_widgets_with(:amount_cents,
          filter: {not: {name: {equal_to_any_of: [nil, "thing1"]}}})

        expect(widgets).to match([
          string_hash_of(widget2, :id, :amount_cents)
        ])

        # Test that a filter param set to 'nil' is accepted, and is treated
        # the same as that filter param being omitted.
        widgets = list_widgets_with(:amount_cents,
          filter: {id: {equal_to_any_of: nil}},
          order_by: [:amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget1, :id, :amount_cents),
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # The negation of an empty predicate is an always false filter. `{not: {equal_to_any_of: nil}}`
        # evaluates to `{not: {true}}`, therefore the filter will match no documents.
        widgets = list_widgets_with(:amount_cents,
          filter: {id: {not: {equal_to_any_of: nil}}},
          order_by: [:amount_cents_ASC])

        expect(widgets).to match []

        # Test that sorting by the same field twice in different directions doesn't fail.
        # (The extra sort should be effectively ignored).
        widgets = list_widgets_with(:amount_cents, order_by: [:amount_cents_DESC, :amount_cents_ASC])

        expect(widgets).to match([
          string_hash_of(widget3, :id, :amount_cents),
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget1, :id, :amount_cents)
        ])

        widgets = list_widgets_via_widgets_or_addresses(filter: {id: {equal_to_any_of: [widget1.fetch(:id)]}})
        expect(widgets).to contain_exactly({"id" => widget1.fetch(:id)})

        widgets = list_widgets_via_widgets_or_addresses(filter: {id: {not: {equal_to_any_of: [widget1.fetch(:id)]}}})
        expect(widgets).to contain_exactly({"id" => widget2.fetch(:id)}, {"id" => widget3.fetch(:id)})

        # Test that we can query for widgets with ignored routing values
        widgets = list_widgets_with(:workspace_id,
          filter: {"workspace_id" => {"equal_to_any_of" => ["workspace_1", "ignored_workspace_2"]}},
          order_by: [:amount_cents_ASC])
        expect(widgets).to match([
          string_hash_of(widget1, :id, :workspace_id),
          string_hash_of(widget2, :id, :workspace_id)
        ])

        widgets = list_widgets_with(:workspace_id,
          filter: {"workspace_id" => {"not" => {"equal_to_any_of" => ["workspace_1", "ignored_workspace_2"]}}},
          order_by: [:amount_cents_ASC])
        expect(widgets).to match([
          string_hash_of(widget3, :id, :workspace_id)
        ])

        widgets = list_widgets_by_nodes_with(nil, allow_errors: false, first: 1)
        expect(widgets).to match([
          string_hash_of(widget3, :id)
        ])

        unfiltered_widget_currencies = list_widget_currencies_by_nodes(first: 1)
        expect(unfiltered_widget_currencies).to match([{
          "id" => "USD",
          case_correctly("widget_names") => {
            case_correctly("page_info") => {
              case_correctly("end_cursor") => /\w+/,
              case_correctly("start_cursor") => /\w+/,
              case_correctly("has_next_page") => false,
              case_correctly("has_previous_page") => false
            },
            case_correctly("total_edge_count") => 2,
            "nodes" => ["thing1", "thing2"]
          },
          case_correctly("widget_options") => {
            "colors" => [enum_value("BLUE"), enum_value("RED")],
            "sizes" => [enum_value("MEDIUM"), enum_value("SMALL")]
          },
          case_correctly("widget_tags") => ["abc", "def", "ghi", "jkl", "mno", "pqr"],
          case_correctly("widget_fee_currencies") => ["CAD", "USD"]
        }])

        full_text_search_results = list_widgets_with(:name, filter: {"name_text" => {matches: "thing1"}}, order_by: [:name_ASC])
        expect(full_text_search_results).to match([
          string_hash_of(widget1, :id, :name)
        ])

        full_text_query_search_results = list_widgets_with(:name, filter: {"name_text" => {matches_query: {query: "thing1"}}}, order_by: [:name_ASC])
        expect(full_text_query_search_results).to match([
          string_hash_of(widget1, :id, :name),
          string_hash_of(widget2, :id, :name)
        ])

        # Try passing an explicit `nil` for the `allowed_edits_per_term` parameter; it should get a GraphQL validation error instead of a runtime Exception.
        response = query_widgets_with(:name, allow_errors: true, filter: {"name_text" => {matches_query: {query: "thing1", allowed_edits_per_term: nil}}}, order_by: [:name_ASC])
        expect(response["errors"].size).to eq(1)
        expect(response.dig("errors", 0)).to include("message" => a_string_including("Argument '#{case_correctly "allowed_edits_per_term"}'", "has an invalid value (null)."))

        full_text_query_no_fuzziness_search_results = list_widgets_with(:name, filter: {"name_text" => {matches_query: {query: "thing1", allowed_edits_per_term: :NONE}}}, order_by: [:name_ASC])
        expect(full_text_query_no_fuzziness_search_results).to match([
          string_hash_of(widget1, :id, :name)
        ])

        phrase_search_results = list_widgets_with(:name, filter: {"name_text" => {matches_phrase: {phrase: "thin"}}}, order_by: [:name_ASC])
        expect(phrase_search_results).to match([
          string_hash_of(widget1, :id, :name),
          string_hash_of(widget2, :id, :name)
        ])

        # Test all_of with complex combinations
        widgets = list_widgets_with(:amount_cents,
          filter: {
            "all_of" => [
              {
                "any_of" => [
                  {"tags" => {"any_satisfy" => {"equal_to_any_of" => ["abc"]}}},
                  {"amount_cents" => {"gt" => 150}}
                ]
              },
              {
                "any_of" => [
                  {"tags" => {"any_satisfy" => {"equal_to_any_of" => ["unfound_tag"]}}},
                  {"amount_cents" => {"lt" => 150}}
                ]
              }
            ]
          })

        expect(widgets).to eq([
          string_hash_of(widget1, :id, :amount_cents)
        ])

        # Test all_of with not
        widgets = list_widgets_with(:amount_cents,
          filter: {
            "all_of" => [
              {"amount_cents" => {"gt" => 50}},
              {"not" => {"tags" => {"any_satisfy" => {"equal_to_any_of" => ["ghi"]}}}}
            ]
          },
          order_by: [:amount_cents_ASC])

        expect(widgets).to eq([
          string_hash_of(widget1, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Test not: {all_of: [...]}
        widgets = list_widgets_with(:amount_cents,
          filter: {
            "not" => {
              "all_of" => [
                {"amount_cents" => {"gt" => 150}},
                {"tags" => {"any_satisfy" => {"equal_to_any_of" => ["ghi"]}}}
              ]
            }
          },
          order_by: [:amount_cents_ASC])

        expect(widgets).to eq([
          string_hash_of(widget1, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Test all_of with empty filter
        widgets = list_widgets_with(:amount_cents,
          filter: {
            "all_of" => [
              {}, # matches all documents
              {"amount_cents" => {"gt" => 150}}
            ]
          },
          order_by: [:amount_cents_ASC])

        expect(widgets).to eq([
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Test all_of with empty predicates
        widgets = list_widgets_with(:amount_cents,
          filter: {
            "all_of" => [
              {"tags" => {}}, # matches all documents
              {"amount_cents" => {"gt" => 150}}
            ]
          },
          order_by: [:amount_cents_ASC])

        expect(widgets).to eq([
          string_hash_of(widget2, :id, :amount_cents),
          string_hash_of(widget3, :id, :amount_cents)
        ])

        # Test all_of with not and empty predicates
        widgets = list_widgets_with(:amount_cents,
          filter: {
            "all_of" => [
              {"not" => {}}, # matches no documents
              {"amount_cents" => {"gt" => 50}}
            ]
          },
          order_by: [:amount_cents_ASC])

        expect(widgets).to eq([])
      end

      it "supports fetching interface fields" do
        index_into(
          graphql,
          build(:widget, name: "w1", inventor: build(:person, name: "Bob", nationality: "Ukrainian")),
          build(:widget, name: "w2", inventor: build(:company, name: "Clippy", stock_ticker: "CLIP")),
          build(:component, name: "c1", created_at: "2021-01-01T12:30:00Z"),
          build(:electrical_part, name: "e1"),
          build(:mechanical_part, name: "m1"),
          build(:manufacturer, name: "m2")
        )

        results = call_graphql_query(<<~EOS).dig("data", case_correctly("named_entities"), "edges").map { |e| e["node"] }
          query {
            named_entities(order_by: [name_ASC]) {
              edges {
                node {
                  name

                  ... on Widget {
                    named_inventor {
                      name

                      ... on Person {
                        nationality
                      }

                      ... on Company {
                        stock_ticker
                      }
                    }
                  }

                  ... on Component {
                    created_at
                  }
                }
              }
            }
          }
        EOS

        expect(results).to eq [
          {"name" => "c1", case_correctly("created_at") => "2021-01-01T12:30:00.000Z"},
          {"name" => "e1"},
          {"name" => "m1"},
          {"name" => "m2"},
          {"name" => "w1", case_correctly("named_inventor") => {"name" => "Bob", "nationality" => "Ukrainian"}},
          {"name" => "w2", case_correctly("named_inventor") => {"name" => "Clippy", case_correctly("stock_ticker") => "CLIP"}}
        ]
      end

      describe "`list` filtering behavior" do
        it "supports filtering on scalar lists, nested object lists, and embedded object lists", :expect_index_exclusions do
          index_records(
            build(
              :team,
              id: "t1",
              details: build(:team_details, count: 5),
              past_names: ["Pilots", "Pink Sox"],
              won_championships_at: [],
              forbes_valuations: [200_000_000, 5],
              seasons: [build(:team_season, record: build(:team_record, wins: 50, losses: 12))],
              current_players: [
                build(:player, name: "Babe Truth", nicknames: ["The Truth"], seasons: [
                  build(:player_season, awards: ["MVP", "Rookie of the Year", "Cy Young"], games_played: 160),
                  build(:player_season, awards: ["Gold Glove"], games_played: 120)
                ])
              ]
            ),
            build(
              :team,
              id: "t2",
              details: build(:team_details, count: 15),
              past_names: ["Pink Sox"],
              won_championships_at: ["2013-11-27T02:30:00Z", "2013-11-27T22:30:00Z"],
              forbes_valuations: [],
              seasons: [
                build(:team_season, record: build(:team_record, wins: 100, losses: 12)),
                build(:team_season, record: build(:team_record, wins: 3, losses: 60))
              ],
              current_players: [
                build(:player, name: "Babe Truth", nicknames: ["The Babe", "Bambino"], seasons: [
                  build(:player_season, awards: ["Silver Slugger"], games_played: 100)
                ]),
                build(:player, name: "Johnny Rocket", nicknames: ["The Rocket"], seasons: [])
              ]
            ),
            build(
              :team,
              id: "t3",
              details: build(:team_details, count: 4),
              past_names: ["Pilots"],
              won_championships_at: ["2003-10-27T19:30:00Z"],
              forbes_valuations: [0, 50_000_000, 100_000_000],
              seasons: [build(:team_season, record: build(:team_record, wins: 50, losses: 12))],
              current_players: [
                build(:player, name: "Ichiro", nicknames: ["Bambino"], seasons: [
                  build(:player_season, awards: ["MVP"], games_played: 50, year: nil),
                  build(:player_season, awards: ["RoY"], games_played: 90, year: nil)
                ]),
                build(:player, name: "Babe Truth", nicknames: ["The Wizard"], seasons: [
                  build(:player_season, awards: ["Gold Glove"], games_played: 150)
                ])
              ]
            ),
            build(
              :team,
              details: build(:team_details, count: 12),
              id: "t4",
              past_names: [],
              won_championships_at: ["2005-10-27T12:30:00Z"],
              forbes_valuations: [42],
              seasons: [build(:team_season, record: build(:team_record, wins: 50, losses: 12))],
              current_players: []
            )
          )

          # Verify that if we filter on a rollover field with a range that excludes all indices, we get back no results rather than an
          # "indices are not configured" error.
          teams = query_teams_with(filter: {formed_on: {gt: "9999-01-01"}})
          expect(teams).to eq []

          # Verify `any_satisfy: {...}` with all null predicates on a list-of-scalars field.
          results = query_teams_with(filter: {past_names: {any_satisfy: {equal_to_any_of: nil}}})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify `any_satisfy: {...}` with all null predicates on a nested field.
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {name: {equal_to_any_of: nil}}}})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify `any_satisfy: {...}` on a list-of-scalars field.
          results = query_teams_with(filter: {past_names: {any_satisfy: {equal_to_any_of: ["Pilots", "Other"]}}})
          # t1 and t3 both have Pilots as a past name.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]

          # Verify `any_satisfy: {...}` on a list-of-numbers field with range operators.
          results = query_teams_with(filter: {forbes_valuations: {any_satisfy: {gt: 50_000}}})
          # t1 and t3 both have a valuation > 50,000.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {forbes_valuations: {any_satisfy: {gt: 1, lt: 100}}})
          # t1 and t3 both have a valuation in the exclusive range 1 to 100.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t4"}]

          # Verify `not: {any_satisfy: ...}` on a list-of-scalars field.
          results = query_teams_with(filter: {past_names: {not: {any_satisfy: {equal_to_any_of: ["Pilots", "Other"]}}}})
          # t2 matches because it does not have Pilots or Other in its list of names.
          # t4 matches because its list of names is empty, and therefore does not have Pilots or Other in its list of names.
          expect(results).to eq [{"id" => "t2"}, {"id" => "t4"}]

          # Verify `any_satisfy: {time_of_day: ...}` on a list-of-timestamps field.
          results = query_teams_with(filter: {won_championships_at: {any_satisfy: {time_of_day: {gt: "15:00:00"}}}})
          expect(results).to eq [{"id" => "t2"}, {"id" => "t3"}]

          # Verify `any_satisfy: {any_of: [...]}` on a list-of-scalars field.
          results = query_teams_with(filter: {forbes_valuations: {any_satisfy: {any_of: []}}})
          expect(results).to eq []
          results = query_teams_with(filter: {forbes_valuations: {any_satisfy: {any_of: [{gt: 50_000}]}}})
          # t1 and t3 both have a valuation > 50,000.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {forbes_valuations: {any_satisfy: {any_of: [{gt: 150_000_000}, {lt: 5}]}}})
          # t1 has 200_000_000; t3 has 0
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]

          # Verify we can use the `any_satisfy` filter operator on a list-of-nested objects correctly.
          # Also, verify that the sub-objects are considered independently. Team t3 has a player with the name
          # "Babe Truth" and a player with the nickname "Bambino", but they aren't the same player so it should
          # not match.
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {
            name: {equal_to_any_of: ["Babe Truth"]},
            nicknames: {any_satisfy: {equal_to_any_of: ["Bambino"]}}
          }}})
          expect(results).to eq [{"id" => "t2"}]

          # Verify we can use `not` on a single field within an `any_satisfy`.
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {
            name: {equal_to_any_of: ["Babe Truth"]},
            nicknames: {not: {any_satisfy: {equal_to_any_of: ["Bambino"]}}}
          }}})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]

          # Verify we can use `not` directly under `any_satisfy` on a nested field.
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {not: {
            name: {equal_to_any_of: ["Babe Truth"]},
            nicknames: {any_satisfy: {equal_to_any_of: ["Bambino"]}}
          }}}})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}]

          # Verify `any_of: [emptyPredicate]` returns all results.
          results = query_teams_with(filter: {any_of: [{forbes_valuations: nil}]})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify `any_of: [emptyPredicate, nonEmptyPredicate]` returns all results.
          results = query_teams_with(filter: {any_of: [{forbes_valuations: nil}, {id: {equal_to_any_of: ["t3"]}}]})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify we can use `any_of` directly under `any_satisfy` on a nested field.
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {any_of: [
            {name: {equal_to_any_of: ["Johnny Rocket"]}},
            {nicknames: {any_satisfy: {equal_to_any_of: ["The Truth"]}}}
          ]}}})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}]

          # Verify `count` filtering on a root list-of-scalars field
          results = query_teams_with(filter: {past_names: {count: {gt: 1}}})
          # t1 has 2 past_names.
          expect(results).to eq [{"id" => "t1"}]

          # Verify `count` nil filtering on a root list-of-scalars field
          results = query_teams_with(filter: {past_names: {count: {gt: nil}}})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify `count` filtering on a list-of-nested field
          results = query_teams_with(filter: {current_players_nested: {count: {gt: 1}}})
          # t2 and t3 have 2 players each.
          expect(results).to eq [{"id" => "t2"}, {"id" => "t3"}]

          # Verify `count` nil filtering on a list-of-nested field
          results = query_teams_with(filter: {current_players_nested: {count: {gt: nil}}})
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify `count` filtering on a list-of-object field
          results = query_teams_with(filter: {current_players_object: {count: {gt: 1}}})
          # t2 and t3 have 2 players each.
          expect(results).to eq [{"id" => "t2"}, {"id" => "t3"}]

          # Verify `count` on a scalar field under a list-of-object field
          results = query_teams_with(filter: {current_players_object: {name: {count: {gt: 1}}}})
          # teams t2 and t3 have 2 players, each with a name.
          expect(results).to eq [{"id" => "t2"}, {"id" => "t3"}]

          # Verify `count` on a scalar field under a list-of-object field does not count `nil` values as part of the field's total count
          results = query_teams_with(filter: {current_players_object: {seasons_object: {year: {count: {lt: 2}}}}})
          # t1 has 1 player, with 2 seasons, each of which has `year` set, so it is not included.
          # t2 has 2 players--one with 1 season, one with zero seasons--so it is included.
          # t3 has 2 players with 3 total seasons; however on two of those, the year is `nil`, so the collection of player season years has only one element, so it's included.
          # t4 has no players, so the count is effectively 0, so it is included.
          expect(results).to eq [{"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify that a `count` schema field (distinct from the `count` operator on a list field) can still be filtered on
          results = query_teams_with(filter: {details: {count: {gt: 10}}})
          # t2 and t4 have details.count of 12 and 15
          expect(results).to eq [{"id" => "t2"}, {"id" => "t4"}]
          results = query_teams_with(filter: {seasons_object: {count: {any_satisfy: {gt: 0}}}})
          # All 4 teams have `count` values on their `seasons`.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]
          results = query_teams_with(filter: {seasons_object: {count: {count: {gt: 0}}}})
          # All 4 teams have `count` values on their `seasons`.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify the `count` of a subfield of an empty list is treated as 0
          results = query_teams_with(filter: {current_players_object: {nicknames: {count: {lt: 1}}}})
          # t4 has no players, so the count of `current_players_object.nicknames` is 0.
          expect(results).to eq [{"id" => "t4"}]

          # Verify `any_satisfy` and `count` on a list-of-object-of-objects field
          results = query_teams_with(filter: {current_players_object: {seasons_object: {awards: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}})
          # t1 and t3 both have players who have won an MVP
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_object: {seasons_object: {awards: {not: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}}})
          # t2 and t4 both have no current players who have won an MVP award
          expect(results).to eq [{"id" => "t2"}, {"id" => "t4"}]
          results = query_teams_with(filter: {current_players_object: {seasons_object: {games_played: {any_satisfy: {any_of: [{gt: 150}, {lt: 100}]}}}}})
          # t1 and t3 have players with > 150 games played or < 100 games played
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_object: {seasons_object: {awards: {count: {gte: 3}}}}})
          # t1 has 4 awards and t3 has 3 awards
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]

          # Verify `any_satisfy` and `count` on a list-of-object-of-nested field
          results = query_teams_with(filter: {current_players_object: {seasons_nested: {any_satisfy: {awards: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}}})
          # t1 and t3 both have players who have won an MVP
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_object: {seasons_nested: {any_satisfy: {awards: {not: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}}}})
          # t1, t2 and t3 all have a player with a season in which they did not win MVP
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_object: {seasons_nested: {any_satisfy: {games_played: {any_of: [{gt: 150}, {lt: 100}]}}}}})
          # t1 and t3 have players with > 150 games played or < 100 games played
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_object: {seasons_nested: {any_satisfy: {awards: {count: {gt: 2}}}}}})
          # t1 has a a player with a season with more than 2 awards
          expect(results).to eq [{"id" => "t1"}]

          # Verify `any_satisfy` and `count` on a list-of-nested-of-nested field
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_nested: {any_satisfy: {awards: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}}}})
          # t1 and t3 both have players who have won an MVP
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_nested: {any_satisfy: {awards: {not: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}}}}})
          # t1, t2 and t3 all have a player with a season in which they did not win MVP
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_nested: {any_satisfy: {games_played: {any_of: [{gt: 150}, {lt: 100}]}}}}}})
          # t1 and t3 have players with > 150 games played or < 100 games played
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_nested: {any_satisfy: {awards: {count: {gt: 2}}}}}}})
          # t1 has a a player with a season with more than 2 awards
          expect(results).to eq [{"id" => "t1"}]

          # Verify `any_satisfy` and `count` on a list-of-nested-of-objects field
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_object: {awards: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}}})
          # t1 and t3 both have players who have won an MVP
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_object: {awards: {not: {any_satisfy: {equal_to_any_of: ["MVP"]}}}}}}})
          # t2 and t3 both have a player who has never won the MVP award
          expect(results).to eq [{"id" => "t2"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_object: {games_played: {any_satisfy: {any_of: [{gt: 150}, {lt: 100}]}}}}}})
          # t1 and t3 have players with > 150 games played or < 100 games played
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}]
          results = query_teams_with(filter: {current_players_nested: {any_satisfy: {seasons_object: {awards: {count: {gt: 2}}}}}})
          # t1 has a a player with a season with more than 2 awards
          expect(results).to eq [{"id" => "t1"}]

          # Verify `all_of: [...]` with 2 `any_satisfy` sub-clauses.
          results = query_teams_with(filter: {seasons_nested: {all_of: [
            # Note: we chose these fields (`record`, `wins`) because they use an alternate `name_in_index`,
            # and we want to verify that field name translation under `all_of` works correctly.
            {any_satisfy: {record: {wins: {gt: 95}}}},
            {any_satisfy: {record: {wins: {lt: 10}}}}
          ]}})
          # Only t2 has a season with more than 95 wins and a season with less than 10 wins
          expect(results).to eq [{"id" => "t2"}]

          # Verify `all_of: [{not: null}]` works as expected.
          results = query_teams_with(filter: {seasons_nested: {all_of: [{not: nil}]}})
          # No teams should be returned since the `nil` part of the filter expression evaluates to `true`.
          expect(results).to eq []

          # Verify `not: {all_of: [...]}` works as expected
          results = query_teams_with(filter: {seasons_nested: {not: {all_of: [
            {any_satisfy: {record: {wins: {gt: 95}}}},
            {any_satisfy: {record: {wins: {lt: 10}}}}
          ]}}})
          # Only t1, t3, and t4 should be returned as they do NOT have both a season with >95 wins AND a season with <10 wins
          expect(results).to eq [{"id" => "t1"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify `all_of: [{not: null}]` works as expected.
          results = query_teams_with(filter: {seasons_nested: {all_of: [{all_of: nil}]}})
          # All teams should be returned since the `nil` part of the filter expression is treated as `true`.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]

          # Verify `all_of: [{}]` works as expected.
          results = query_teams_with(filter: {seasons_nested: {all_of: [{}]}})
          # All teams should be returned since the `nil` part of the filter expression is treated as `true`.
          expect(results).to eq [{"id" => "t1"}, {"id" => "t2"}, {"id" => "t3"}, {"id" => "t4"}]
        end

        it "statically (through the schema) disallows some filter features that do not work well with `any_satisfy`" do
          # `any_satisfy: {not: ...}` disallowed because we cannot implement it to work as a client would expect.
          expect_error_from(
            {past_names: {any_satisfy: {not: {equal_to_any_of: ["Pilots", "Other"]}}}},
            "InputObject '#{apply_derived_type_customizations("StringListElementFilterInput")}' doesn't accept argument 'not'"
          )

          # `any_satisfy: {equal_to_any_of: [null]}` disallowed because we cannot implement it to work as a client would expect
          # That looks like it would match a list field with a `null` element, but the `exists` operator we use for `equal_to_any_of: [null]`
          # doesn't support that:
          # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/query-dsl-exists-query.html
          expect_error_from(
            {past_names: {any_satisfy: {equal_to_any_of: [nil]}}},
            "Argument '#{case_correctly "equal_to_any_of"}' on InputObject '#{apply_derived_type_customizations("StringListElementFilterInput")}' has an invalid value ([null])"
          )

          # `any_satisfy: {[multiple predicates that translate to distinct clauses]}` disallowed because the datastore does not require them to all be true of the same value to match a document
          expect_error_from(
            {forbes_valuations: {any_satisfy: {gt: 100, equal_to_any_of: [5]}}},
            "`#{case_correctly "any_satisfy"}: {#{case_correctly "equal_to_any_of"}: [5], gt: 100}` is not supported because it produces multiple filtering clauses under `#{case_correctly "any_satisfy"}`"
          )
        end

        def query_teams_with(expect_errors: false, **query_args)
          results = call_graphql_query(<<~QUERY, allow_errors: expect_errors)
            query {
              teams#{graphql_args(query_args)} {
                nodes {
                  id
                }
              }
            }
          QUERY

          expect_errors ? results.to_h : results.dig("data", "teams", "nodes")
        end

        def expect_error_from(filter, *error_snippets)
          expect {
            results = query_teams_with(filter: filter, expect_errors: true)
            expect(results.dig("errors", 0, "message")).to include(*error_snippets)
          }.to log_warning(a_string_including(*error_snippets))
        end
      end

      context "when multiple sources flow into the same index" do
        it "automatically excludes documents that have not received data from their primary `__self` source" do
          index_records(
            build(:widget, id: "w1", name: "Pre-Thingy", component_ids: ["c23", "c47"]),
            build(:component, id: "c23", name: "C")
          )

          nodes = call_graphql_query(<<~QUERY).dig("data", "components", "nodes")
            query {
              components { nodes { id } }
            }
          QUERY

          expect(nodes).to eq [{"id" => "c23"}]
        end
      end

      context "with nested fields" do
        let(:widget1) { build(:widget, options: build(:widget_options, color: "RED"), inventor: build(:person)) }
        let(:widget2) { build(:widget, options: build(:widget_options, color: "BLUE"), inventor: build(:company)) }

        before do
          index_records(widget1, widget2)
        end

        it "loads nested fields, with filtering support" do
          expected_widget1 = string_hash_of(widget1, :id, :name, :amount_cents,
            options: string_hash_of(widget1[:options], :size),
            inventor: string_hash_of(widget1[:inventor], :name, :nationality))

          expected_widget2 = string_hash_of(widget2, :id, :name, :amount_cents,
            options: string_hash_of(widget2[:options], :size),
            inventor: string_hash_of(widget2[:inventor], :name, :stock_ticker))

          expect(list_widgets_with_options_and_inventor).to contain_exactly(expected_widget1, expected_widget2)

          expect(list_widgets_with_options_and_inventor(
            filter: {options: {color: {equal_to_any_of: [enum_value(:RED)]}}}
          )).to contain_exactly(expected_widget1)

          expect(list_widgets_with_options_and_inventor(
            filter: {not: {options: {color: {equal_to_any_of: [enum_value(:RED)]}}}}
          )).to contain_exactly(expected_widget2)

          # equal_to_any_of set to 'nil' should not cause any filtering on that value.
          expect(list_widgets_with_options_and_inventor(
            filter: {options: {color: {equal_to_any_of: nil}}}
          )).to contain_exactly(expected_widget1, expected_widget2)

          # `{not: emptyPredicate}` should result in an always false filter
          expect(list_widgets_with_options_and_inventor(
            filter: {options: {color: {not: {equal_to_any_of: nil}}}}
          )).to eq []

          # `{not: nil}` should result in an always false filter
          expect(list_widgets_with_options_and_inventor(
            filter: {options: {color: {not: nil}}}
          )).to eq []

          # On type unions you can filter on a subfield that is present on all subtypes...
          expect(list_widgets_with_options_and_inventor(
            filter: {inventor: {name: {equal_to_any_of: [widget1.fetch(:inventor).fetch(:name)]}}}
          )).to contain_exactly(expected_widget1)

          expect(list_widgets_with_options_and_inventor(
            filter: {inventor: {name: {not: {equal_to_any_of: [widget1.fetch(:inventor).fetch(:name)]}}}}
          )).to contain_exactly(expected_widget2)

          stock_ticker_key = case_correctly("stock_ticker").to_sym
          # ...or on a subfield that is present on only some subtypes...
          expect(list_widgets_with_options_and_inventor(
            filter: {inventor: {stock_ticker_key => {equal_to_any_of: [widget2.fetch(:inventor).fetch(stock_ticker_key)]}}}
          )).to contain_exactly(expected_widget2)

          expect(list_widgets_with_options_and_inventor(
            filter: {inventor: {stock_ticker_key => {not: {equal_to_any_of: [widget2.fetch(:inventor).fetch(stock_ticker_key)]}}}}
          )).to contain_exactly(expected_widget1)

          # On interfaces you can filter on a subfield that is present on all subtypes...
          expect(list_widgets_with_options_and_inventor(
            filter: {named_inventor: {name: {equal_to_any_of: [widget1.fetch(:inventor).fetch(:name)]}}}
          )).to contain_exactly(expected_widget1)

          expect(list_widgets_with_options_and_inventor(
            filter: {named_inventor: {name: {not: {equal_to_any_of: [widget1.fetch(:inventor).fetch(:name)]}}}}
          )).to contain_exactly(expected_widget2)

          stock_ticker_key = case_correctly("stock_ticker").to_sym
          # ...or on a subfield that is present on only some subtypes...
          expect(list_widgets_with_options_and_inventor(
            filter: {named_inventor: {stock_ticker_key => {equal_to_any_of: [widget2.fetch(:inventor).fetch(stock_ticker_key)]}}}
          )).to contain_exactly(expected_widget2)

          expect(list_widgets_with_options_and_inventor(
            filter: {named_inventor: {stock_ticker_key => {not: {equal_to_any_of: [widget2.fetch(:inventor).fetch(stock_ticker_key)]}}}}
          )).to contain_exactly(expected_widget1)

          # ...or on `__typename`. Well, you could if the GraphQL spec allowed input fields
          # named `__typename`, but it does not (see http://spec.graphql.org/June2018/#sec-Input-Objects)
          # so we do not yet support it.
          # expect(list_widgets_with_options_and_inventor(
          #   filter: { inventor: { __typename: { equal_to_any_of: ["Company"] } } }
          # )).to contain_exactly(expected_widget2)
        end
      end

      def list_widgets_with(fieldname, **query_args)
        query_widgets_with(fieldname, **query_args).dig("data", "widgets", "edges").map { |we| we.fetch("node") }
      end

      def list_widgets_and_page_info_with(fieldname, **query_args)
        response = query_widgets_with(fieldname, **query_args).dig("data", "widgets")

        page_info = response.fetch(case_correctly("page_info"))
        nodes = response.fetch("edges").map { |we| we.fetch("node") }

        [nodes, page_info]
      end

      def list_widgets_via_widgets_or_addresses(**query_args)
        call_graphql_query(<<~QUERY).dig("data", case_correctly("widgets_or_addresses"), "edges").map { |we| we.fetch("node") }
          query {
            widgets_or_addresses#{graphql_args(query_args)} {
              edges {
                node {
                  ...on Widget {
                    id
                  }
                }
              }
            }
          }
        QUERY
      end

      def list_widgets_by_nodes_with(fieldname, **query_args)
        query_widgets_by_nodes_with(fieldname, **query_args).dig("data", "widgets", "nodes")
      end

      def query_widgets_by_nodes_with(fieldname, allow_errors: false, **query_args)
        call_graphql_query(<<~QUERY, allow_errors: allow_errors)
          query {
            widgets#{graphql_args(query_args)} {
              nodes {
                id
                #{fieldname}
              }
            }
          }
        QUERY
      end

      def query_widgets_with(fieldname, allow_errors: false, **query_args)
        call_graphql_query(<<~QUERY, allow_errors: allow_errors)
          query {
            widgets#{graphql_args(query_args)} {
              page_info {
                end_cursor
                has_next_page
              }
              edges {
                node {
                  id
                  #{fieldname}
                }
              }
            }
          }
        QUERY
      end

      def list_widget_currencies(**query_args)
        call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_currencies"), "edges").map { |we| we.fetch("node") }
          query {
            widget_currencies#{graphql_args(query_args)} {
              edges {
                node {
                  id
                  widget_names {
                    page_info {
                      start_cursor
                      end_cursor
                      has_next_page
                      has_previous_page
                    }

                    total_edge_count

                    edges {
                      node
                      cursor
                    }
                  }
                  widget_tags
                  widget_fee_currencies
                  widget_options {
                    sizes
                    colors
                  }
                }
              }
            }
          }
        QUERY
      end

      def list_widget_currencies_by_nodes(**query_args)
        call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_currencies"), "nodes")
          query {
            widget_currencies#{graphql_args(query_args)} {
              nodes {
                id
                widget_names {
                  page_info {
                    start_cursor
                    end_cursor
                    has_next_page
                    has_previous_page
                  }

                  total_edge_count

                  nodes
                }
                widget_tags
                widget_fee_currencies
                widget_options {
                  sizes
                  colors
                }
              }
            }
          }
        QUERY
      end

      def list_widgets_with_options_and_inventor(**widget_query_args)
        call_graphql_query(<<~QUERY).dig("data", "widgets", "edges").map { |we| we.fetch("node") }
          query {
            widgets#{graphql_args(widget_query_args)} {
              edges {
                node {
                  id
                  name
                  amount_cents

                  inventor {
                    ... on Person {
                      name
                      nationality
                    }

                    ... on Company {
                      name
                      stock_ticker
                    }
                  }

                  options {
                    size
                  }
                }
              }
            }
          }
        QUERY
      end
    end
  end
end
