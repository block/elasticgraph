# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"
require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"
require "elastic_graph/graphql/datastore_query"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--aggregations" do
    include_context "ElasticGraph GraphQL acceptance aggregation support"

    with_both_casing_forms do
      let(:amount_cents) { case_correctly("amount_cents") }
      let(:aggregated_values) { case_correctly("aggregated_values") }
      let(:grouped_by) { case_correctly("grouped_by") }
      let(:approximate_distinct_value_count) { case_correctly("approximate_distinct_value_count") }

      it "returns empty aggregation results when the indices have not been configured or no documents have been indexed" do
        allow(GraphQL::DatastoreQuery).to receive(:perform).and_wrap_original do |original, queries, &block|
          queries.each do |query|
            original_to_datastore_msearch_header = query.to_datastore_msearch_header
            to_datastore_msearch_header =
              if original_to_datastore_msearch_header[:index].start_with?("widgets")
                original_to_datastore_msearch_header.merge(index: "rollover_index_with_no_concrete_indexes__*")
              else
                original_to_datastore_msearch_header
              end

            allow(query).to receive(:to_datastore_msearch_header).and_return(to_datastore_msearch_header)
          end

          original.call(queries, &block)
        end

        # Test grouped_by
        expect_indices_not_configured_error { group_widgets_by_tag(allow_errors: true) }
        # Test aggregated_values
        expect_indices_not_configured_error { list_widgets_with_aggregations(all_amount_aggregations, allow_errors: true) }
      end

      it "returns aggregates (terms, date histogram) and nested aggregates" do
        # Test grouped_by before anything is indexed
        aggregations = group_widgets_by_tag
        expect(aggregations).to eq []

        # Test aggregated_values before anything is indexed.
        aggregations = list_widgets_with_aggregations(all_amount_aggregations)
        expect(aggregations).to contain_exactly({
          aggregated_values => {
            amount_cents => expected_aggregated_amounts_of([]),
            "cost" => {amount_cents => expected_aggregated_amounts_of([])}
          },
          "count" => 0
        })

        ten_usd_and_cad = [{currency: "USD", amount_cents: 1000}, {currency: "CAD", amount_cents: 1000}]
        index_records(
          # we build some components in order to have some data for our `components` query that exercises an edge case,
          # and also to support grouping on a numeric field (position x and y)
          component = build(:component, position: {x: 10, y: 20}),
          build(:component, position: {x: 10, y: 30}),
          widget1 = build(:widget, name: "w100", amount_cents: 100, options: build(:widget_options, size: "SMALL", color: "BLUE", is_draft: false), cost_currency: "USD", created_at: "2019-06-01T12:02:20Z", release_timestamps: ["2019-06-01T12:02:20Z", "2019-06-04T19:19:19Z"], components: [component], tags: [], fees: []),
          build(:widget, name: "w200", amount_cents: 200, options: build(:widget_options, size: "SMALL", color: "RED", is_draft: true), cost_currency: "GBP", created_at: "2019-06-02T12:02:20Z", release_timestamps: ["2019-06-02T12:02:20Z"], tags: ["small", "red"], fees: ten_usd_and_cad),
          build(:widget, name: "w300", amount_cents: 300, options: build(:widget_options, size: "MEDIUM", color: "RED", is_draft: false), cost_currency: "USD", created_at: "2019-06-01T13:03:30Z", release_timestamps: ["2019-06-01T13:03:30Z"], tags: ["medium", "red", "red"], fees: [])
        )

        # Verify that we can group on a list field (which groups by the individual values of that field)
        aggregations = group_widgets_by_tag
        expect(aggregations).to eq [
          {
            grouped_by => {"tag" => nil},
            "count" => 1,
            aggregated_values => {
              "#{amount_cents}1" => {"sum" => 100},
              "#{amount_cents}2" => {"sum" => 100}
            }
          },
          {
            grouped_by => {"tag" => "medium"},
            "count" => 1,
            aggregated_values => {
              "#{amount_cents}1" => {"sum" => 300},
              "#{amount_cents}2" => {"sum" => 300}
            }
          },
          {
            grouped_by => {"tag" => "red"},
            "count" => 2, # demonstrates that a document isn't included in a grouping twice even if its list has that value twice.
            aggregated_values => {
              "#{amount_cents}1" => {"sum" => 500},
              "#{amount_cents}2" => {"sum" => 500}
            }
          },
          {
            grouped_by => {"tag" => "small"},
            "count" => 1,
            aggregated_values => {
              "#{amount_cents}1" => {"sum" => 200},
              "#{amount_cents}2" => {"sum" => 200}
            }
          }
        ]

        # Verify that we can group on a subfield of list of objects field (which groups by the individual values of that field)
        aggregations = group_widgets_by_fees_currency_with_approximate_distinct_value_counts
        expect(aggregations).to eq [
          {
            grouped_by => {"fees" => {"currency" => nil}},
            "count" => 2,
            aggregated_values => {amount_cents => {"sum" => 400}, "id" => {approximate_distinct_value_count => 2}, "tags" => {approximate_distinct_value_count => 2}}
          },
          {
            grouped_by => {"fees" => {"currency" => "CAD"}},
            "count" => 1,
            aggregated_values => {amount_cents => {"sum" => 200}, "id" => {approximate_distinct_value_count => 1}, "tags" => {approximate_distinct_value_count => 2}}
          },
          {
            grouped_by => {"fees" => {"currency" => "USD"}},
            "count" => 1,
            aggregated_values => {amount_cents => {"sum" => 200}, "id" => {approximate_distinct_value_count => 1}, "tags" => {approximate_distinct_value_count => 2}}
          }
        ]

        # Verify that we can group on a graphql-only field which is an alias for a child field.
        aggregations = list_widgets_with_aggregations(amount_aggregation("size"))
        expect(aggregations).to match [
          {
            grouped_by => {"size" => enum_value("MEDIUM")},
            "count" => 1,
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            }
          },
          {
            grouped_by => {"size" => enum_value("SMALL")},
            "count" => 2,
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100, 200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100, 200)}
            }
          }
        ]

        # Verify that `aggregated_values` supports a graphql-only field which is an alias for a child field
        size_uniq_count = widget_ungrouped_aggregated_values_for("size { approximate_distinct_value_count }")
        expect(size_uniq_count).to eq({"size" => {case_correctly("approximate_distinct_value_count") => 2}})

        aggregations = group_widget_currencies_by_widget_name
        expect(aggregations).to eq [
          {"count" => 1, case_correctly("grouped_by") => {case_correctly("widget_name") => "w100"}},
          {"count" => 1, case_correctly("grouped_by") => {case_correctly("widget_name") => "w200"}},
          {"count" => 1, case_correctly("grouped_by") => {case_correctly("widget_name") => "w300"}}
        ]

        # Verify non-group aggregations
        aggregations = list_widgets_with_aggregations(amount_aggregation)

        expect(aggregations).to contain_exactly({
          aggregated_values => {
            amount_cents => expected_aggregated_amounts_of(100, 200, 300),
            "cost" => {amount_cents => expected_aggregated_amounts_of(100, 200, 300)}
          },
          "count" => 3
        })

        # Verify single grouping aggregations
        expected_aggs = [
          {
            grouped_by => {
              "options" => {"size" => enum_value("MEDIUM")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              "options" => {"size" => enum_value("SMALL")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100, 200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100, 200)}
            },
            "count" => 2
          }
        ]
        aggregations = list_widgets_with_aggregations(amount_aggregation("options.size", first: 1))
        expect(aggregations).to match([expected_aggs.first]).or match([expected_aggs.last])

        aggregations = list_widgets_with_aggregations(amount_aggregation("options.size", first: 0))
        expect(aggregations).to eq([])

        aggregations = list_widgets_with_aggregations(amount_aggregation("options.size"))
        expect(aggregations).to match_array(expected_aggs)

        # Verify that the same query, when aggregating on a numeric field with divergent index/graphql field names, works properly.
        aggregations_with_divergent_agg_field_names = list_widgets_with_aggregations(
          amount_aggregation("options.size").sub("amount_cents", "amount_cents2")
        )
        expect(aggregations_with_divergent_agg_field_names).to eq(aggregations.map do |agg|
          agg.merge(aggregated_values => agg.fetch(aggregated_values).transform_keys do |k|
            (k == case_correctly("amount_cents")) ? case_correctly("amount_cents2") : k
          end)
        end)

        # Verify that the same query, when grouping a leaf field that has a divergent index/graphql field name, works properly.
        aggregations_with_divergent_field_names = list_widgets_with_aggregations(amount_aggregation("options.the_size"))

        expected_result_with_divergent_field_names = aggregations.map do |agg|
          agg_grouped_by = agg.fetch(grouped_by)

          updated_options = agg_grouped_by.fetch("options")
            .merge(case_correctly("the_size") => agg_grouped_by.dig("options", "size"))
            .except("size")

          agg.merge(grouped_by => agg_grouped_by.merge("options" => updated_options))
        end
        expect(aggregations_with_divergent_field_names).to eq(expected_result_with_divergent_field_names)

        # Verify single grouping aggregation on an nested field
        aggregations = list_widgets_with_aggregations(amount_aggregation("cost.currency"))

        expect(aggregations).to contain_exactly(
          {
            grouped_by => {
              "cost" => {"currency" => "USD"}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100, 300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100, 300)}
            },
            "count" => 2
          },
          {
            grouped_by => {
              "cost" => {"currency" => "GBP"}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # Verify single grouping aggregation on a boolean field
        aggregations = list_widgets_with_aggregations(amount_aggregation("options.is_draft"))

        expect(aggregations).to contain_exactly(
          {
            grouped_by => {
              "options" => {case_correctly("is_draft") => false}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100, 300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100, 300)}
            },
            "count" => 2
          },
          {
            grouped_by => {
              "options" => {case_correctly("is_draft") => true}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # Verify single grouping on a numeric field
        x_and_y_groupings = group_components_by_position_x_and_y
        expect(x_and_y_groupings).to eq({
          case_correctly("by_x") => {"edges" => [
            {"node" => {"count" => 2, grouped_by => {"position" => {"x" => 10}}}}
          ]},
          case_correctly("by_y") => {"edges" => [
            {"node" => {"count" => 1, grouped_by => {"position" => {"y" => 20}}}},
            {"node" => {"count" => 1, grouped_by => {"position" => {"y" => 30}}}}
          ]}
        })

        # Verify multiple grouping aggregations
        aggregations = list_widgets_with_aggregations(amount_aggregation("options.size", "options.color"))

        expect(aggregations).to contain_exactly(
          {
            grouped_by => {
              "options" => {"size" => enum_value("SMALL"), "color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              "options" => {"size" => enum_value("SMALL"), "color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              "options" => {"size" => enum_value("MEDIUM"), "color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          }
        )

        # Verify that the same query, when grouping on subfields of a parent field that has a divergent index/graphql field name, works properly.
        aggregations_with_divergent_field_names = list_widgets_with_aggregations(amount_aggregation("the_options.the_size", "the_options.color"))

        expect(aggregations_with_divergent_field_names).to contain_exactly(
          {
            grouped_by => {
              case_correctly("the_options") => {case_correctly("the_size") => enum_value("SMALL"), "color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("the_options") => {case_correctly("the_size") => enum_value("SMALL"), "color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("the_options") => {case_correctly("the_size") => enum_value("MEDIUM"), "color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          }
        )

        # Verify date/time aggregations
        # DateTime: as_date_time()
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_at {as_date_time(truncation_unit: DAY)}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_date_time") => "2019-06-01T00:00:00.000Z"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_date_time") => "2019-06-01T00:00:00.000Z"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_date_time") => "2019-06-02T00:00:00.000Z"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # DateTime: as_date()
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_at {as_date(truncation_unit: DAY)}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_date") => "2019-06-01"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_date") => "2019-06-01"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_date") => "2019-06-02"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # DateTime: as_day_of_week() for a scalar field (`DateTime!`)
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_at {as_day_of_week}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_day_of_week") => enum_value("SATURDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_day_of_week") => enum_value("SATURDAY")
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_day_of_week") => enum_value("SUNDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # DateTime: as_day_of_week() for a list of scalar fields (`[DateTime!]!`)
        aggregations = list_widgets_with_aggregations(amount_aggregation("release_timestamp {as_day_of_week(offset: {amount: -1, unit: DAY})}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_day_of_week") => enum_value("FRIDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_day_of_week") => enum_value("FRIDAY")
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_day_of_week") => enum_value("SATURDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_day_of_week") => enum_value("MONDAY") # 2nd DateTime value in list for widget1
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          }
        )

        # DateTime: as_time_of_day() truncated to SECOND
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_at {as_time_of_day(truncation_unit: SECOND)}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "12:02:20"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "12:02:20"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "13:03:30"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          }
        )

        # DateTime: as_time_of_day() truncated to MINUTE
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_at {as_time_of_day(truncation_unit: MINUTE)}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "12:02:00"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "12:02:00"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "13:03:00"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          }
        )

        # DateTime: as_time_of_day() truncated to HOUR
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_at {as_time_of_day(truncation_unit: HOUR)}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "12:00:00"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "12:00:00"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at") => {
                case_correctly("as_time_of_day") => "13:00:00"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          }
        )

        # DateTime: as_time_of_day() for a list of scalar fields (`[DateTime!]!`)
        aggregations = list_widgets_with_aggregations(amount_aggregation("release_timestamp {as_time_of_day(truncation_unit: MINUTE, offset: {amount: -3, unit: HOUR})}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_time_of_day") => "09:02:00"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_time_of_day") => "09:02:00"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_time_of_day") => "10:03:00"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_timestamp") => {
                case_correctly("as_time_of_day") => "16:19:00"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          }
        )

        # Date: as_date()
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_on {as_date(truncation_unit: DAY)}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_on") => {
                case_correctly("as_date") => "2019-06-01"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_on") => {
                case_correctly("as_date") => "2019-06-01"
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_on") => {
                case_correctly("as_date") => "2019-06-02"
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # Date: as_day_of_week()
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_on {as_day_of_week}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_on") => {
                case_correctly("as_day_of_week") => enum_value("SATURDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_on") => {
                case_correctly("as_day_of_week") => enum_value("SATURDAY")
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_on") => {
                case_correctly("as_day_of_week") => enum_value("SUNDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # Date: as_day_of_week() for a list of scalar fields (`[Date!]!`)
        aggregations = list_widgets_with_aggregations(amount_aggregation("release_date {as_day_of_week(offset: {amount: 2, unit: DAY})}", "options.color"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("release_date") => {
                case_correctly("as_day_of_week") => enum_value("MONDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_date") => {
                case_correctly("as_day_of_week") => enum_value("MONDAY")
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_date") => {
                case_correctly("as_day_of_week") => enum_value("TUESDAY")
              }, "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("release_date") => {
                case_correctly("as_day_of_week") => enum_value("THURSDAY") # 2nd Date value in list for widget1
              }, "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          }
        )

        verify_all_timestamp_groupings_valid(widget1.fetch(:id), truncation_unit_type: "DateTimeGroupingTruncationUnitInput", field: "created_at")
        verify_all_datetime_offset_units_valid(widget1.fetch(:id))

        # Legacy date/time grouping API
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_at_legacy(granularity: DAY)", "options.color"))

        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_at_legacy") => "2019-06-01T00:00:00.000Z",
              "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at_legacy") => "2019-06-01T00:00:00.000Z",
              "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_at_legacy") => "2019-06-02T00:00:00.000Z",
              "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        # Verify date histogram groupings when the datetime field has a different name in the index
        aggs_with_divergent_date_field_names = list_widgets_with_aggregations(amount_aggregation("created_at2_legacy(granularity: DAY)", "options.color"))
        expect(aggs_with_divergent_date_field_names).to eq(aggregations.map do |agg|
          agg.merge(grouped_by => agg.fetch(grouped_by).transform_keys do |k|
            (k == case_correctly("created_at_legacy")) ? case_correctly("created_at2_legacy") : k
          end)
        end)

        # Verify that grouping on the same timestamp field at different granularities succeeds (even though it's not really useful...).
        aggregations = list_widgets_with_aggregations(amount_aggregation("by_day: created_at_legacy(granularity: DAY)", "by_month: created_at_legacy(granularity: MONTH)"))
        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("by_day") => "2019-06-01T00:00:00.000Z",
              case_correctly("by_month") => "2019-06-01T00:00:00.000Z"
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100, 300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100, 300)}
            },
            "count" => 2
          },
          {
            grouped_by => {
              case_correctly("by_day") => "2019-06-02T00:00:00.000Z",
              case_correctly("by_month") => "2019-06-01T00:00:00.000Z"
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        legacy_verify_all_timestamp_groupings_valid(widget1.fetch(:id), granularity_type: "DateTimeGroupingGranularityInput", field: "created_at_legacy")
        legacy_verify_all_datetime_offset_units_valid(widget1.fetch(:id))

        # Verify date histogram groupings
        aggregations = list_widgets_with_aggregations(amount_aggregation("created_on_legacy(granularity: DAY)", "options.color"))

        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_on_legacy") => "2019-06-01",
              "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(300)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_on_legacy") => "2019-06-01",
              "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          },
          {
            grouped_by => {
              case_correctly("created_on_legacy") => "2019-06-02",
              "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200)}
            },
            "count" => 1
          }
        )

        aggregations = list_widgets_with_aggregations(amount_aggregation("created_on_legacy(granularity: MONTH, offset_days: 4)", "options.color"))

        expect(aggregations).to include(
          {
            grouped_by => {
              case_correctly("created_on_legacy") => "2019-05-05", # When we shift the date boundaries 4 days, 2019-06-01 falls into the month bucket starting 2019-05-05
              "options" => {"color" => enum_value("RED")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(200, 300),
              "cost" => {amount_cents => expected_aggregated_amounts_of(200, 300)}
            },
            "count" => 2
          },
          {
            grouped_by => {
              case_correctly("created_on_legacy") => "2019-05-05",
              "options" => {"color" => enum_value("BLUE")}
            },
            aggregated_values => {
              amount_cents => expected_aggregated_amounts_of(100),
              "cost" => {amount_cents => expected_aggregated_amounts_of(100)}
            },
            "count" => 1
          }
        )

        legacy_verify_all_timestamp_groupings_valid(widget1.fetch(:id), granularity_type: "DateGroupingGranularityInput", field: "created_on_legacy")
      end

      def expected_aggregated_amounts_of(*raw_values)
        raw_values = raw_values.flatten # to allow an empty array to be passed for explicitness
        min = raw_values.min
        max = raw_values.max
        sum = raw_values.sum
        avg = raw_values.empty? ? nil : sum.to_f / raw_values.size

        {
          case_correctly("approximate_sum") => float_of(sum),
          case_correctly("exact_sum") => int_of(sum),
          case_correctly("approximate_avg") => float_of(avg),
          case_correctly("exact_min") => int_of(min),
          case_correctly("exact_max") => int_of(max)
        }
      end

      def verify_all_timestamp_groupings_valid(widget_id, truncation_unit_type:, field:)
        truncation_unit_type = apply_derived_type_customizations(truncation_unit_type)
        datetime_granularities = graphql.schema.type_named(truncation_unit_type).graphql_type.values.keys

        datetime_granularities.each do |truncation_unit|
          aggregations = list_widgets_with_aggregations(amount_aggregation("#{field} { as_date_time(truncation_unit: #{truncation_unit})}"))

          expect(aggregations).not_to be_empty, "Expected valid results for grouping truncation_unit #{truncation_unit}, got: #{aggregations.inspect}"

          if truncation_unit.to_s == "WEEK"
            # Elasticsearch/OpenSearch do not document which day they treat as the first day of week for WEEK groupings.
            # We've observed that they treat Monday as the first day, and have documented it as such. Here
            # we verify that that still holds true so that we know our documentation is accurate.
            #
            # We rely on this in the documentation generated in this file:
            # elasticgraph-schema_definition/lib/elastic_graph/schema_definition/schema_elements/built_in_types.rb
            timestamps_are_mondays = aggregations.map { |a| ::Date.iso8601(a.fetch(case_correctly("grouped_by")).fetch(case_correctly(field)).fetch(case_correctly("as_date_time"))).monday? }.uniq
            expect(timestamps_are_mondays).to eq [true]
          end
        end
      end

      def legacy_verify_all_timestamp_groupings_valid(widget_id, granularity_type:, field:)
        granularity_type = apply_derived_type_customizations(granularity_type)
        datetime_granularities = graphql.schema.type_named(granularity_type).graphql_type.values.keys

        datetime_granularities.each do |granularity|
          aggregations = list_widgets_with_aggregations(amount_aggregation("#{field}(granularity: #{granularity})"))

          expect(aggregations).not_to be_empty, "Expected valid results for grouping granularity #{granularity}, got: #{aggregations.inspect}"

          if granularity.to_s == "WEEK"
            # Elasticsearch/OpenSearch do not document which day they treat as the first day of week for WEEK groupings.
            # We've observed that they treat Monday as the first day, and have documented it as such. Here
            # we verify that that still holds true so that we know our documentation is accurate.
            #
            # We rely on this in the documentation generated in this file:
            # elasticgraph-schema_definition/lib/elastic_graph/schema_definition/schema_elements/built_in_types.rb
            timestamps_are_mondays = aggregations.map { |a| ::Date.iso8601(a.fetch(case_correctly("grouped_by")).fetch(case_correctly(field))).monday? }.uniq
            expect(timestamps_are_mondays).to eq [true]
          end
        end
      end

      def verify_all_datetime_offset_units_valid(widget_id)
        date_time_unit = apply_derived_type_customizations("DateTimeUnitInput")
        agg_queries = graphql.schema.type_named(date_time_unit).graphql_type.values.keys.map do |unit|
          <<~EOS
            #{unit}: widget_aggregations {
              edges {
                node {
                  grouped_by {
                    created_at {
                      as_date_time(truncation_unit: MONTH, offset: {amount: 4, unit: #{unit}})
                    }
                  }
                  count
                }
              }
            }
          EOS
        end

        results = call_graphql_query(<<~QUERY)
          query {
            DAY_FOR_HOUR: widget_aggregations {
              edges {
                node {
                  grouped_by {
                    # Verify that when the offset is much larger than the grouping truncation_unit, it does something reasonable even though this isn't useful.
                    created_at {
                      as_date_time(truncation_unit: HOUR, offset: {amount: 4, unit: DAY})
                    }
                  }
                  count
                }
              }
            }

            #{agg_queries.join("\n")}
          }
        QUERY

        timestamps_by_unit = results.dig("data").to_h do |k, v|
          [k, v.dig("edges", 0, "node", case_correctly("grouped_by"), case_correctly("created_at"))]
        end

        expect(timestamps_by_unit).to eq({
          "DAY_FOR_HOUR" => {case_correctly("as_date_time") => "2019-06-01T12:00:00.000Z"}, # When grouping by hour but offset by 4 days, the offset is effectively ignored.
          "DAY" => {case_correctly("as_date_time") => "2019-05-05T00:00:00.000Z"}, # 2019-06-01 falls into the month starting 2019-05-05 after the shift
          "HOUR" => {case_correctly("as_date_time") => "2019-06-01T04:00:00.000Z"},
          "MINUTE" => {case_correctly("as_date_time") => "2019-06-01T00:04:00.000Z"},
          "SECOND" => {case_correctly("as_date_time") => "2019-06-01T00:00:04.000Z"},
          "MILLISECOND" => {case_correctly("as_date_time") => "2019-06-01T00:00:00.004Z"}
        })
      end

      def legacy_verify_all_datetime_offset_units_valid(widget_id)
        date_time_unit = apply_derived_type_customizations("DateTimeUnitInput")
        agg_queries = graphql.schema.type_named(date_time_unit).graphql_type.values.keys.map do |unit|
          <<~EOS
            #{unit}: widget_aggregations {
              edges {
                node {
                  grouped_by {
                    created_at_legacy(granularity: MONTH, offset: {amount: 4, unit: #{unit}})
                  }
                  count
                }
              }
            }
          EOS
        end

        results = call_graphql_query(<<~QUERY)
          query {
            DAY_FOR_HOUR: widget_aggregations {
              edges {
                node {
                  grouped_by {
                    # Verify that when the offset is much larger than the grouping granularity, it does something reasonable even though this isn't useful.
                    created_at_legacy(granularity: HOUR, offset: {amount: 4, unit: DAY})
                  }
                  count
                }
              }
            }

            #{agg_queries.join("\n")}
          }
        QUERY

        timestamps_by_unit = results.dig("data").to_h do |k, v|
          [k, v.dig("edges", 0, "node", case_correctly("grouped_by"), case_correctly("created_at_legacy"))]
        end

        expect(timestamps_by_unit).to eq({
          "DAY_FOR_HOUR" => "2019-06-01T12:00:00.000Z", # When grouping by hour but offset by 4 days, the offset is effectively ignored.
          "DAY" => "2019-05-05T00:00:00.000Z", # 2019-06-01 falls into the month starting 2019-05-05 after the shift
          "HOUR" => "2019-06-01T04:00:00.000Z",
          "MINUTE" => "2019-06-01T00:04:00.000Z",
          "SECOND" => "2019-06-01T00:00:04.000Z",
          "MILLISECOND" => "2019-06-01T00:00:00.004Z"
        })
      end

      it "supports all IANA timezone ids for timestamp grouping" do
        index_records(build(:widget, created_at: "2022-11-23T03:00:00Z"))

        agg_queries = GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.map.with_index do |time_zone, index|
          # Use 2 different args as part of our assertions on the impact of `Aggregation::QueryOptimizer`.
          args =
            if time_zone.start_with?("America/")
              {filter: {"id" => {"not" => {"equal_to_any_of" => [nil]}}}}
            else
              {}
            end

          <<~EOS
            tz#{index}: widget_aggregations#{graphql_args(args)} {
              edges {
                node {
                  grouped_by {
                    created_at {
                      as_date_time(truncation_unit: DAY, time_zone: "#{time_zone}")
                    }
                  }
                  count
                }
              }
            }
          EOS
        end

        # If the datastore does not understand any of our timestamp values, we'll get an exception and this will fail here.
        results = call_graphql_query(<<~QUERY)
          query {
            #{agg_queries.join("\n")}
          }
        QUERY

        uniq_timestamps = results.dig("data").map { |k, v| v.dig("edges", 0, "node", case_correctly("grouped_by"), case_correctly("created_at"), case_correctly("as_date_time")) }.uniq

        # Here we verify that the `created_at` values we got back run the gamut from -12:00 to +12:00,
        # demonstrating that `created_at` values are correctly converted to values in the specified time zone.
        # There are some additional values we're not asserting on here (such as `+03:30...) but we don't need
        # to be exhaustive here.
        expect(uniq_timestamps).to include(
          "2022-11-22T00:00:00.000-12:00",
          "2022-11-22T00:00:00.000-11:00",
          "2022-11-22T00:00:00.000-10:00",
          "2022-11-22T00:00:00.000-09:00",
          "2022-11-22T00:00:00.000-08:00",
          "2022-11-22T00:00:00.000-07:00",
          "2022-11-22T00:00:00.000-06:00",
          "2022-11-22T00:00:00.000-05:00",
          "2022-11-22T00:00:00.000-04:00",
          # Since the `created_at` timestamp is at `03:00:00Z`, the ones above here are on 2022-11-22, and the ones below on 2022-11-23.
          "2022-11-23T00:00:00.000-03:00",
          "2022-11-23T00:00:00.000-02:00",
          "2022-11-23T00:00:00.000-01:00",
          "2022-11-23T00:00:00.000Z",
          "2022-11-23T00:00:00.000+01:00",
          "2022-11-23T00:00:00.000+02:00",
          "2022-11-23T00:00:00.000+03:00",
          "2022-11-23T00:00:00.000+04:00",
          "2022-11-23T00:00:00.000+05:00",
          "2022-11-23T00:00:00.000+06:00",
          "2022-11-23T00:00:00.000+07:00",
          "2022-11-23T00:00:00.000+08:00",
          "2022-11-23T00:00:00.000+09:00",
          "2022-11-23T00:00:00.000+10:00",
          "2022-11-23T00:00:00.000+11:00",
          "2022-11-23T00:00:00.000+12:00"
        )

        expect(datastore_msearch_requests("main").size).to eq 1

        # Due to our `Aggregation::QueryOptimizer`, we're able to serve this with 2 searches in a single msearch request.
        # It would be 1, but we intentionally are using `filter` for some aggregations and omitting it for others in order
        # to demonstrate that separate searches are used when filters differ.
        expect(count_of_searches_in(datastore_msearch_requests("main").first)).to eq 2

        # Verify that we logged positive values for `elasticgraph_overhead_ms` and `datastore_server_duration_ms`
        # to ensure our detailed duration tracking is working end-to-end. We check it in this test because this
        # query is one of the slowest ones in our test suite. Some of the others are fast enough that we can't
        # always count on positive values for both numbers here even when things are working correctly.
        expect(logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration").last).to include(
          "elasticgraph_overhead_ms" => a_value > 0,
          "datastore_server_duration_ms" => a_value > 0
        )
      end

      it "supports all IANA timezone ids for legacy timestamp grouping" do
        index_records(build(:widget, created_at: "2022-11-23T03:00:00Z"))

        agg_queries = GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.map.with_index do |time_zone, index|
          # Use 2 different args as part of our assertions on the impact of `Aggregation::QueryOptimizer`.
          args =
            if time_zone.start_with?("America/")
              {filter: {"id" => {"not" => {"equal_to_any_of" => [nil]}}}}
            else
              {}
            end

          <<~EOS
            tz#{index}: widget_aggregations#{graphql_args(args)} {
              edges {
                node {
                  grouped_by {
                    created_at_legacy(granularity: DAY, time_zone: "#{time_zone}")
                  }
                  count
                }
              }
            }
          EOS
        end

        # If the datastore does not understand any of our timestamp values, we'll get an exception and this will fail here.
        results = call_graphql_query(<<~QUERY)
          query {
            #{agg_queries.join("\n")}
          }
        QUERY

        uniq_timestamps = results.dig("data").map { |k, v| v.dig("edges", 0, "node", case_correctly("grouped_by"), case_correctly("created_at_legacy")) }.uniq

        # Here we verify that the `created_at_legacy` values we got back run the gamut from -12:00 to +12:00,
        # demonstrating that `created_at_legacy` values are correctly converted to values in the specified time zone.
        # There are some additional values we're not asserting on here (such as `+03:30...) but we don't need
        # to be exhaustive here.
        expect(uniq_timestamps).to include(
          "2022-11-22T00:00:00.000-12:00",
          "2022-11-22T00:00:00.000-11:00",
          "2022-11-22T00:00:00.000-10:00",
          "2022-11-22T00:00:00.000-09:00",
          "2022-11-22T00:00:00.000-08:00",
          "2022-11-22T00:00:00.000-07:00",
          "2022-11-22T00:00:00.000-06:00",
          "2022-11-22T00:00:00.000-05:00",
          "2022-11-22T00:00:00.000-04:00",
          # Since the `created_at_legacy` timestamp is at `03:00:00Z`, the ones above here are on 2022-11-22, and the ones below on 2022-11-23.
          "2022-11-23T00:00:00.000-03:00",
          "2022-11-23T00:00:00.000-02:00",
          "2022-11-23T00:00:00.000-01:00",
          "2022-11-23T00:00:00.000Z",
          "2022-11-23T00:00:00.000+01:00",
          "2022-11-23T00:00:00.000+02:00",
          "2022-11-23T00:00:00.000+03:00",
          "2022-11-23T00:00:00.000+04:00",
          "2022-11-23T00:00:00.000+05:00",
          "2022-11-23T00:00:00.000+06:00",
          "2022-11-23T00:00:00.000+07:00",
          "2022-11-23T00:00:00.000+08:00",
          "2022-11-23T00:00:00.000+09:00",
          "2022-11-23T00:00:00.000+10:00",
          "2022-11-23T00:00:00.000+11:00",
          "2022-11-23T00:00:00.000+12:00"
        )

        expect(datastore_msearch_requests("main").size).to eq 1

        # Due to our `Aggregation::QueryOptimizer`, we're able to serve this with 2 searches in a single msearch request.
        # It would be 1, but we intentionally are using `filter` for some aggregations and omitting it for others in order
        # to demonstrate that separate searches are used when filters differ.
        expect(count_of_searches_in(datastore_msearch_requests("main").first)).to eq 2

        # Verify that we logged positive values for `elasticgraph_overhead_ms` and `datastore_server_duration_ms`
        # to ensure our detailed duration tracking is working end-to-end. We check it in this test because this
        # query is one of the slowest ones in our test suite. Some of the others are fast enough that we can't
        # always count on positive values for both numbers here even when things are working correctly.
        expect(logged_jsons_of_type("ElasticGraphQueryExecutorQueryDuration").last).to include(
          "elasticgraph_overhead_ms" => a_value > 0,
          "datastore_server_duration_ms" => a_value > 0
        )
      end

      it "supports grouping and counting on a type union or an interface" do
        index_into(
          graphql,
          build(:electrical_part, name: "p1"),
          build(:mechanical_part, name: "p1"),
          build(:mechanical_part, name: "p2")
        )

        # Run on aggregation on a type union (`parts`)
        results = call_graphql_query(<<~EOS).dig("data", case_correctly("part_aggregations"), "edges").map { |e| e["node"] }
          query {
            part_aggregations {
              edges {
                node {
                  grouped_by { name }
                  count
                }
              }
            }
          }
        EOS

        expect(results).to contain_exactly(
          {case_correctly("grouped_by") => {"name" => "p1"}, "count" => 2},
          {case_correctly("grouped_by") => {"name" => "p2"}, "count" => 1}
        )

        # Run on aggregation on an interface (`named_entities`)
        results = call_graphql_query(<<~EOS).dig("data", case_correctly("named_entity_aggregations"), "edges").map { |e| e["node"] }
          query {
            named_entity_aggregations {
              edges {
                node {
                  grouped_by { name }
                  count
                }
              }
            }
          }
        EOS

        expect(results).to contain_exactly(
          {case_correctly("grouped_by") => {"name" => "p1"}, "count" => 2},
          {case_correctly("grouped_by") => {"name" => "p2"}, "count" => 1}
        )
      end

      it "supports using aggregations only for counts" do
        index_records(
          build(:widget, amount_cents: 100, options: build(:widget_options, size: "SMALL", color: "BLUE"), created_at: "2019-06-01T12:00:00Z"),
          build(:widget, amount_cents: 200, options: build(:widget_options, size: "SMALL", color: "RED"), created_at: "2019-06-02T12:00:00Z"),
          build(:widget, amount_cents: 300, options: build(:widget_options, size: "MEDIUM", color: "RED"), created_at: "2019-06-01T12:00:00Z")
        )

        # Verify non-group aggregations
        aggregations = list_widgets_with_aggregations(count_aggregation)

        expect(aggregations).to contain_exactly(
          {"count" => 3}
        )

        # Verify single grouping aggregations
        aggregations = list_widgets_with_aggregations(count_aggregation("options.size"))

        expect(aggregations).to contain_exactly(
          {grouped_by => {"options" => {"size" => enum_value("MEDIUM")}}, "count" => 1},
          {grouped_by => {"options" => {"size" => enum_value("SMALL")}}, "count" => 2}
        )

        # Verify multiple grouping aggregations
        aggregations = list_widgets_with_aggregations(count_aggregation("options.size", "options.color"))

        expect(aggregations).to contain_exactly(
          {grouped_by => {"options" => {"size" => enum_value("SMALL"), "color" => enum_value("RED")}}, "count" => 1},
          {grouped_by => {"options" => {"size" => enum_value("SMALL"), "color" => enum_value("BLUE")}}, "count" => 1},
          {grouped_by => {"options" => {"size" => enum_value("MEDIUM"), "color" => enum_value("RED")}}, "count" => 1}
        )

        # Verify date histogram groupings
        aggregations = list_widgets_with_aggregations(count_aggregation("created_at { as_date_time(truncation_unit: DAY) }", "options.color"))

        expect(aggregations).to include(
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2019-06-01T00:00:00.000Z"}, "options" => {"color" => enum_value("RED")}}, "count" => 1},
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2019-06-01T00:00:00.000Z"}, "options" => {"color" => enum_value("BLUE")}}, "count" => 1},
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2019-06-02T00:00:00.000Z"}, "options" => {"color" => enum_value("RED")}}, "count" => 1}
        )
      end

      it "supports using legacy aggregations only for counts" do
        index_records(
          build(:widget, amount_cents: 100, options: build(:widget_options, size: "SMALL", color: "BLUE"), created_at: "2019-06-01T12:00:00Z"),
          build(:widget, amount_cents: 200, options: build(:widget_options, size: "SMALL", color: "RED"), created_at: "2019-06-02T12:00:00Z"),
          build(:widget, amount_cents: 300, options: build(:widget_options, size: "MEDIUM", color: "RED"), created_at: "2019-06-01T12:00:00Z")
        )

        # Verify non-group aggregations
        aggregations = list_widgets_with_aggregations(count_aggregation)

        expect(aggregations).to contain_exactly(
          {"count" => 3}
        )

        # Verify single grouping aggregations
        aggregations = list_widgets_with_aggregations(count_aggregation("options.size"))

        expect(aggregations).to contain_exactly(
          {grouped_by => {"options" => {"size" => enum_value("MEDIUM")}}, "count" => 1},
          {grouped_by => {"options" => {"size" => enum_value("SMALL")}}, "count" => 2}
        )

        # Verify multiple grouping aggregations
        aggregations = list_widgets_with_aggregations(count_aggregation("options.size", "options.color"))

        expect(aggregations).to contain_exactly(
          {grouped_by => {"options" => {"size" => enum_value("SMALL"), "color" => enum_value("RED")}}, "count" => 1},
          {grouped_by => {"options" => {"size" => enum_value("SMALL"), "color" => enum_value("BLUE")}}, "count" => 1},
          {grouped_by => {"options" => {"size" => enum_value("MEDIUM"), "color" => enum_value("RED")}}, "count" => 1}
        )

        # Verify date histogram groupings
        aggregations = list_widgets_with_aggregations(count_aggregation("created_at_legacy(granularity: DAY)", "options.color"))

        expect(aggregations).to include(
          {grouped_by => {case_correctly("created_at_legacy") => "2019-06-01T00:00:00.000Z", "options" => {"color" => enum_value("RED")}}, "count" => 1},
          {grouped_by => {case_correctly("created_at_legacy") => "2019-06-01T00:00:00.000Z", "options" => {"color" => enum_value("BLUE")}}, "count" => 1},
          {grouped_by => {case_correctly("created_at_legacy") => "2019-06-02T00:00:00.000Z", "options" => {"color" => enum_value("RED")}}, "count" => 1}
        )
      end

      it "supports using aggregation on `list of objects` fields" do
        index_records(
          build(:widget, fees: [{amount_cents: 500, currency: "USD"}, {amount_cents: 1500, currency: "USD"}]),
          build(:widget, fees: [{amount_cents: 10, currency: "USD"}]),
          build(:widget, fees: [{amount_cents: 100, currency: "USD"}, {amount_cents: 90, currency: "USD"}])
        )

        result = call_graphql_query(<<~QUERY)
          query {
            widget_aggregations {
              nodes {
                aggregated_values {
                  fees {
                    amount_cents {
                      approximate_sum
                      approximate_avg
                      exact_min
                      exact_max
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(result.dig("data", case_correctly("widget_aggregations"), "nodes")).to contain_exactly({
          case_correctly("aggregated_values") => {
            "fees" => {
              case_correctly("amount_cents") => {
                case_correctly("approximate_sum") => float_of(2200.0),
                case_correctly("approximate_avg") => float_of(440.0),
                case_correctly("exact_min") => int_of(10.0),
                case_correctly("exact_max") => int_of(1500.0)
              }
            }
          }
        })
      end

      it "supports using aggregations for a list of numbers" do
        index_records(
          build(:widget, amounts: [5, 10]),
          build(:widget, amounts: [15]),
          build(:widget, amounts: [20, 25])
        )

        result = call_graphql_query(<<~QUERY)
          query {
            widget_aggregations {
              edges {
                node {
                  aggregated_values {
                    amounts {
                      approximate_sum
                      approximate_avg
                      exact_min
                      exact_max
                    }
                  }
                }
              }
            }
          }
        QUERY

        expect(result.dig("data", case_correctly("widget_aggregations"), "edges")).to contain_exactly({
          "node" => {
            case_correctly("aggregated_values") => {
              "amounts" => {
                case_correctly("approximate_sum") => float_of(75.0),
                case_correctly("approximate_avg") => float_of(15.0),
                case_correctly("exact_min") => int_of(5),
                case_correctly("exact_max") => int_of(25)
              }
            }
          }
        })
      end

      it "supports using aggregations for calendar types (Date, DateTime, LocalTime)" do
        index_records(
          build(:widget, created_at: "2023-10-09T12:30:12.345Z"),
          build(:widget, created_at: "2024-01-09T09:30:12.456Z"),
          build(:widget, created_at: "2023-12-01T22:30:12.789Z")
        )

        result = call_graphql_query(<<~QUERY)
          query {
            widget_aggregations {
              nodes {
                aggregated_values {
                  created_at { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_on { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_at_time_of_day { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                }
              }
            }
          }
        QUERY

        expect(result.dig("data", case_correctly("widget_aggregations"), "nodes")).to contain_exactly({
          case_correctly("aggregated_values") => {
            case_correctly("created_at") => {
              case_correctly("exact_min") => "2023-10-09T12:30:12.345Z",
              case_correctly("exact_max") => "2024-01-09T09:30:12.456Z",
              case_correctly("approximate_avg") => "2023-11-26T22:50:12.530Z",
              case_correctly("approximate_distinct_value_count") => 3
            },
            case_correctly("created_on") => {
              case_correctly("exact_min") => "2023-10-09",
              case_correctly("exact_max") => "2024-01-09",
              case_correctly("approximate_avg") => "2023-11-26",
              case_correctly("approximate_distinct_value_count") => 3
            },
            case_correctly("created_at_time_of_day") => {
              case_correctly("exact_min") => "09:30:12",
              case_correctly("exact_max") => "22:30:12",
              case_correctly("approximate_avg") => "14:50:12",
              case_correctly("approximate_distinct_value_count") => 3
            }
          }
        })
      end

      it "supports using legacy aggregations for calendar types (Date, DateTime, LocalTime)" do
        index_records(
          build(:widget, created_at: "2023-10-09T12:30:12.345Z"),
          build(:widget, created_at: "2024-01-09T09:30:12.456Z"),
          build(:widget, created_at: "2023-12-01T22:30:12.789Z")
        )

        result = call_graphql_query(<<~QUERY)
          query {
            widget_aggregations {
              nodes {
                aggregated_values {
                  created_at_legacy { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_on_legacy { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                  created_at_time_of_day { exact_min, exact_max, approximate_avg, approximate_distinct_value_count }
                }
              }
            }
          }
        QUERY

        expect(result.dig("data", case_correctly("widget_aggregations"), "nodes")).to contain_exactly({
          case_correctly("aggregated_values") => {
            case_correctly("created_at_legacy") => {
              case_correctly("exact_min") => "2023-10-09T12:30:12.345Z",
              case_correctly("exact_max") => "2024-01-09T09:30:12.456Z",
              case_correctly("approximate_avg") => "2023-11-26T22:50:12.530Z",
              case_correctly("approximate_distinct_value_count") => 3
            },
            case_correctly("created_on_legacy") => {
              case_correctly("exact_min") => "2023-10-09",
              case_correctly("exact_max") => "2024-01-09",
              case_correctly("approximate_avg") => "2023-11-26",
              case_correctly("approximate_distinct_value_count") => 3
            },
            case_correctly("created_at_time_of_day") => {
              case_correctly("exact_min") => "09:30:12",
              case_correctly("exact_max") => "22:30:12",
              case_correctly("approximate_avg") => "14:50:12",
              case_correctly("approximate_distinct_value_count") => 3
            }
          }
        })
      end

      it "supports aggregating at different dimensions/granularities in a single GraphQL query using aliases" do
        index_records(
          build(:widget, amount_cents: 100, options: build(:widget_options, size: "SMALL", color: "BLUE"), created_at: "2019-06-01T12:00:00Z"),
          build(:widget, amount_cents: 200, options: build(:widget_options, size: "SMALL", color: "RED"), created_at: "2019-07-02T12:00:00Z"),
          build(:widget, amount_cents: 400, options: build(:widget_options, size: "MEDIUM", color: "RED"), created_at: "2020-06-01T12:00:00Z")
        )

        result = call_graphql_query(<<~QUERY).dig("data")
          query {
            size: widget_aggregations {
              edges {
                node {
                  grouped_by { options { size } }
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            color: widget_aggregations {
              edges {
                node {
                  grouped_by { options { color } }
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            month: widget_aggregations {
              edges {
                node {
                  grouped_by { created_at { as_date_time(truncation_unit: MONTH) }}
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            year: widget_aggregations {
              edges {
                node {
                  grouped_by { created_at { as_date_time(truncation_unit: YEAR) }}
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            avg: widget_aggregations {
              edges {
                node {
                  aggregated_values { amount_cents { approximate_avg } }
                  count
                }
              }
            }

            minmax: widget_aggregations {
              edges {
                node {
                  aggregated_values { amount_cents { exact_min, exact_max } }
                }
              }
            }

            count: widget_aggregations {
              edges {
                node {
                  count
                }
              }
            }
          }
        QUERY

        expect(result.keys).to contain_exactly("size", "color", "month", "year", "avg", "minmax", "count")

        expect(result.fetch("size").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {"options" => {"size" => enum_value("MEDIUM")}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 400}}},
          {grouped_by => {"options" => {"size" => enum_value("SMALL")}}, "count" => 2, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 300}}}
        ]

        expect(result.fetch("color").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {"options" => {"color" => enum_value("BLUE")}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 100}}},
          {grouped_by => {"options" => {"color" => enum_value("RED")}}, "count" => 2, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 600}}}
        ]

        expect(result.fetch("month").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2019-06-01T00:00:00.000Z"}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 100}}},
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2019-07-01T00:00:00.000Z"}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 200}}},
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2020-06-01T00:00:00.000Z"}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 400}}}
        ]

        expect(result.fetch("year").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2019-01-01T00:00:00.000Z"}}, "count" => 2, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 300}}},
          {grouped_by => {case_correctly("created_at") => {case_correctly("as_date_time") => "2020-01-01T00:00:00.000Z"}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 400}}}
        ]

        expect(result.fetch("avg").fetch("edges").map { |e| e["node"] }).to match [
          {"count" => 3, aggregated_values => {case_correctly("amount_cents") => {case_correctly("approximate_avg") => a_value_within(0.1).of(233.3)}}}
        ]

        expect(result.fetch("minmax").fetch("edges").map { |e| e["node"] }).to eq [
          {aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_min") => 100, case_correctly("exact_max") => 400}}}
        ]

        expect(datastore_msearch_requests("main").size).to eq 1
        # We expect only 2 searches in our single msearch request:
        #
        # * 1 for size/color/month/year/minmax
        # * 1 for avg/count
        #
        # avg and count cannot be combined with the others because they request the document count WITHOUT a `grouped_by`.
        # The datastore aggregations API does not provide a way to get a count without grouping; instead you have to request the
        # document count from the main search body. As a result, the `DatastoreQuery` for avg/count has differences from
        # the others beyond just the aggregations. With out current `Aggregation::QueryOptimizer` implementation, we don't
        # combine these.
        expect(count_of_searches_in(datastore_msearch_requests("main").first)).to eq 2
        expect(logged_jsons_of_type("AggregationQueryOptimizerMergedQueries").size).to eq 2
        expect(logged_jsons_of_type("AggregationQueryOptimizerMergedQueries").first).to include(
          "aggregation_names" => ["1_size", "2_color", "3_month", "4_year", "5_minmax"],
          "aggregation_count" => 5
        )
        expect(logged_jsons_of_type("AggregationQueryOptimizerMergedQueries").last).to include(
          "aggregation_names" => ["6_avg", "7_count"],
          "aggregation_count" => 2,
          "query_count" => 2
        )
      end

      it "supports legacy aggregating at different dimensions/granularities in a single GraphQL query using aliases" do
        index_records(
          build(:widget, amount_cents: 100, options: build(:widget_options, size: "SMALL", color: "BLUE"), created_at: "2019-06-01T12:00:00Z"),
          build(:widget, amount_cents: 200, options: build(:widget_options, size: "SMALL", color: "RED"), created_at: "2019-07-02T12:00:00Z"),
          build(:widget, amount_cents: 400, options: build(:widget_options, size: "MEDIUM", color: "RED"), created_at: "2020-06-01T12:00:00Z")
        )

        result = call_graphql_query(<<~QUERY).dig("data")
          query {
            size: widget_aggregations {
              edges {
                node {
                  grouped_by { options { size } }
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            color: widget_aggregations {
              edges {
                node {
                  grouped_by { options { color } }
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            month: widget_aggregations {
              edges {
                node {
                  grouped_by { created_at_legacy(granularity: MONTH) }
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            year: widget_aggregations {
              edges {
                node {
                  grouped_by { created_at_legacy(granularity: YEAR) }
                  count
                  aggregated_values { amount_cents { exact_sum } }
                }
              }
            }

            avg: widget_aggregations {
              edges {
                node {
                  aggregated_values { amount_cents { approximate_avg } }
                  count
                }
              }
            }

            minmax: widget_aggregations {
              edges {
                node {
                  aggregated_values { amount_cents { exact_min, exact_max } }
                }
              }
            }

            count: widget_aggregations {
              edges {
                node {
                  count
                }
              }
            }
          }
        QUERY

        expect(result.keys).to contain_exactly("size", "color", "month", "year", "avg", "minmax", "count")

        expect(result.fetch("size").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {"options" => {"size" => enum_value("MEDIUM")}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 400}}},
          {grouped_by => {"options" => {"size" => enum_value("SMALL")}}, "count" => 2, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 300}}}
        ]

        expect(result.fetch("color").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {"options" => {"color" => enum_value("BLUE")}}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 100}}},
          {grouped_by => {"options" => {"color" => enum_value("RED")}}, "count" => 2, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 600}}}
        ]

        expect(result.fetch("month").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {case_correctly("created_at_legacy") => "2019-06-01T00:00:00.000Z"}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 100}}},
          {grouped_by => {case_correctly("created_at_legacy") => "2019-07-01T00:00:00.000Z"}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 200}}},
          {grouped_by => {case_correctly("created_at_legacy") => "2020-06-01T00:00:00.000Z"}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 400}}}
        ]

        expect(result.fetch("year").fetch("edges").map { |e| e["node"] }).to eq [
          {grouped_by => {case_correctly("created_at_legacy") => "2019-01-01T00:00:00.000Z"}, "count" => 2, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 300}}},
          {grouped_by => {case_correctly("created_at_legacy") => "2020-01-01T00:00:00.000Z"}, "count" => 1, aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_sum") => 400}}}
        ]

        expect(result.fetch("avg").fetch("edges").map { |e| e["node"] }).to match [
          {"count" => 3, aggregated_values => {case_correctly("amount_cents") => {case_correctly("approximate_avg") => a_value_within(0.1).of(233.3)}}}
        ]

        expect(result.fetch("minmax").fetch("edges").map { |e| e["node"] }).to eq [
          {aggregated_values => {case_correctly("amount_cents") => {case_correctly("exact_min") => 100, case_correctly("exact_max") => 400}}}
        ]

        expect(datastore_msearch_requests("main").size).to eq 1
        # We expect only 2 searches in our single msearch request:
        #
        # * 1 for size/color/month/year/minmax
        # * 1 for avg/count
        #
        # avg and count cannot be combined with the others because they request the document count WITHOUT a `grouped_by`.
        # The datastore aggregations API does not provide a way to get a count without grouping; instead you have to request the
        # document count from the main search body. As a result, the `DatastoreQuery` for avg/count has differences from
        # the others beyond just the aggregations. With out current `Aggregation::QueryOptimizer` implementation, we don't
        # combine these.
        expect(count_of_searches_in(datastore_msearch_requests("main").first)).to eq 2
        expect(logged_jsons_of_type("AggregationQueryOptimizerMergedQueries").size).to eq 2
        expect(logged_jsons_of_type("AggregationQueryOptimizerMergedQueries").first).to include(
          "aggregation_names" => ["1_size", "2_color", "3_month", "4_year", "5_minmax"],
          "aggregation_count" => 5
        )
        expect(logged_jsons_of_type("AggregationQueryOptimizerMergedQueries").last).to include(
          "aggregation_names" => ["6_avg", "7_count"],
          "aggregation_count" => 2,
          "query_count" => 2
        )
      end

      it "supports pagination on an aggregation connection when grouping by something" do
        index_records(
          build(:widget, workspace_id: "w1"),
          build(:widget, workspace_id: "w2"),
          build(:widget, workspace_id: "w3"),
          build(:widget, workspace_id: "w2"),
          build(:widget, workspace_id: "w4"),
          build(:widget, workspace_id: "w5")
        )

        forward_paginate_through_workspace_id_groupings
        backward_paginate_through_workspace_id_groupings
      end

      def forward_paginate_through_workspace_id_groupings
        page_info, workspace_nodes = list_widget_workspace_id_groupings(first: 2)

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => true,
          case_correctly("has_previous_page") => false
        )

        expect(workspace_nodes).to eq [
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w1"}},
          {"count" => 2, grouped_by => {case_correctly("workspace_id") => "w2"}}
        ]

        expect {
          response = list_widget_workspace_id_groupings(first: 2, after: [1, 2, 3], expect_errors: true)
          expect(response["errors"]).to contain_exactly(a_hash_including("message" => "Argument 'after' on Field '#{case_correctly("widget_aggregations")}' has an invalid value ([1, 2, 3]). Expected type 'Cursor'."))
        }.to log_warning a_string_including("Argument 'after' on Field '#{case_correctly("widget_aggregations")}' has an invalid value", "[1, 2, 3]")

        broken_cursor = page_info.fetch(case_correctly("end_cursor")) + "-broken"
        expect {
          response = list_widget_workspace_id_groupings(first: 2, after: broken_cursor, expect_errors: true)
          expect(response["errors"]).to contain_exactly(a_hash_including("message" => "Argument 'after' on Field '#{case_correctly("widget_aggregations")}' has an invalid value (#{broken_cursor.inspect}). Expected type 'Cursor'."))
        }.to log_warning a_string_including("Argument 'after' on Field '#{case_correctly("widget_aggregations")}' has an invalid value", broken_cursor)

        page_info, workspace_nodes = list_widget_workspace_id_groupings(first: 2, after: page_info.fetch(case_correctly("end_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => true,
          case_correctly("has_previous_page") => true
        )

        expect(workspace_nodes).to eq [
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w3"}},
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w4"}}
        ]

        page_info, workspace_nodes = list_widget_workspace_id_groupings(first: 2, after: page_info.fetch(case_correctly("end_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => false,
          case_correctly("has_previous_page") => true
        )

        expect(workspace_nodes).to eq [
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w5"}}
        ]

        page_info, workspace_nodes = list_widget_workspace_id_groupings(first: 2, after: page_info.fetch(case_correctly("end_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => nil,
          case_correctly("start_cursor") => nil,
          case_correctly("has_next_page") => false,
          case_correctly("has_previous_page") => true
        )

        expect(workspace_nodes).to eq []
      end

      def backward_paginate_through_workspace_id_groupings
        page_info, workspace_nodes = list_widget_workspace_id_groupings(last: 2)

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => false,
          case_correctly("has_previous_page") => true
        )

        expect(workspace_nodes).to eq [
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w4"}},
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w5"}}
        ]

        page_info, workspace_nodes = list_widget_workspace_id_groupings(last: 2, before: page_info.fetch(case_correctly("start_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => true,
          case_correctly("has_previous_page") => true
        )

        expect(workspace_nodes).to eq [
          {"count" => 2, grouped_by => {case_correctly("workspace_id") => "w2"}},
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w3"}}
        ]

        page_info, workspace_nodes = list_widget_workspace_id_groupings(last: 2, before: page_info.fetch(case_correctly("start_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => true,
          case_correctly("has_previous_page") => false
        )

        expect(workspace_nodes).to eq [
          {"count" => 1, grouped_by => {case_correctly("workspace_id") => "w1"}}
        ]

        page_info, workspace_nodes = list_widget_workspace_id_groupings(last: 2, before: page_info.fetch(case_correctly("start_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => nil,
          case_correctly("start_cursor") => nil,
          case_correctly("has_next_page") => true,
          case_correctly("has_previous_page") => false
        )

        expect(workspace_nodes).to eq []
      end

      def list_widget_workspace_id_groupings(expect_errors: false, **pagination_args)
        results = call_graphql_query(<<~QUERY, allow_errors: expect_errors)
          query {
            widget_aggregations#{graphql_args(pagination_args)} {
              page_info {
                end_cursor
                start_cursor
                has_next_page
                has_previous_page
              }

              edges {
                node {
                  grouped_by {
                    workspace_id
                  }
                  count
                }
              }
            }
          }
        QUERY

        return results if expect_errors

        results = results.dig("data", case_correctly("widget_aggregations"))
        nodes = results.fetch("edges").map { |e| e.fetch("node") }
        [results.fetch(case_correctly("page_info")), nodes]
      end

      it "supports pagination on an ungrouped aggregation connection" do
        index_records(
          build(:widget, amount_cents: 100),
          build(:widget, amount_cents: 200)
        )

        forward_paginate_through_ungrouped_aggregations(
          "count",
          {"count" => 2}
        )
        backward_paginate_through_ungrouped_aggregations(
          "count",
          {"count" => 2}
        )

        forward_paginate_through_ungrouped_aggregations(
          "aggregated_values { amount_cents { exact_sum } }",
          {
            case_correctly("aggregated_values") => {
              case_correctly("amount_cents") => {case_correctly("exact_sum") => 300}
            }
          }
        )
        backward_paginate_through_ungrouped_aggregations(
          "aggregated_values { amount_cents { exact_sum } }",
          {
            case_correctly("aggregated_values") => {
              case_correctly("amount_cents") => {case_correctly("exact_sum") => 300}
            }
          }
        )

        # Verify that we an query just `page_info` (no groupings or aggregated values)
        results = call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_aggregations"), case_correctly("page_info"))
          query {
            widget_aggregations {
              page_info {
                end_cursor
                start_cursor
                has_next_page
                has_previous_page
              }
            }
          }
        QUERY

        expect(results).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => false,
          case_correctly("has_previous_page") => false
        )
      end

      it "supports aggregations on just nodes" do
        index_records(
          build(:widget, name: "a", amount_cents: 100),
          build(:widget, name: "a", amount_cents: 50),
          build(:widget, name: "b", amount_cents: 200)
        )

        results = call_graphql_query(<<~QUERY).dig("data")
          query {
            widget_aggregations {
              nodes {
                grouped_by {
                  name
                }
                aggregated_values {
                  amount_cents {
                    exact_sum
                  }
                }
              }
            }
          }
        QUERY

        expect(results).to eq(case_correctly("widget_aggregations") => {
          "nodes" => [
            {
              case_correctly("grouped_by") => {
                "name" => "a"
              },
              case_correctly("aggregated_values") => {
                case_correctly("amount_cents") => {
                  case_correctly("exact_sum") => 150
                }
              }
            },
            {
              case_correctly("grouped_by") => {
                "name" => "b"
              },
              case_correctly("aggregated_values") => {
                case_correctly("amount_cents") => {
                  case_correctly("exact_sum") => 200
                }
              }
            }
          ]
        })
      end

      def forward_paginate_through_ungrouped_aggregations(select, expected_value)
        page_info, nodes = list_widget_ungrouped_aggregations(select, first: 2)

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => false,
          case_correctly("has_previous_page") => false
        )

        expect(nodes).to eq [expected_value]

        page_info, nodes = list_widget_ungrouped_aggregations(select, first: 2, after: page_info.fetch(case_correctly("end_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => nil,
          case_correctly("start_cursor") => nil,
          case_correctly("has_next_page") => false,
          case_correctly("has_previous_page") => true
        )

        expect(nodes).to eq []
      end

      def backward_paginate_through_ungrouped_aggregations(select, expected_value)
        page_info, nodes = list_widget_ungrouped_aggregations(select, last: 2)

        expect(page_info).to match(
          case_correctly("end_cursor") => /\w+/,
          case_correctly("start_cursor") => /\w+/,
          case_correctly("has_next_page") => false,
          case_correctly("has_previous_page") => false
        )

        expect(nodes).to eq [expected_value]

        page_info, nodes = list_widget_ungrouped_aggregations(select, last: 2, before: page_info.fetch(case_correctly("start_cursor")))

        expect(page_info).to match(
          case_correctly("end_cursor") => nil,
          case_correctly("start_cursor") => nil,
          case_correctly("has_next_page") => true,
          case_correctly("has_previous_page") => false
        )

        expect(nodes).to eq []
      end

      def list_widget_ungrouped_aggregations(select, **pagination_args)
        results = call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_aggregations"))
          query {
            widget_aggregations#{graphql_args(pagination_args)} {
              page_info {
                end_cursor
                start_cursor
                has_next_page
                has_previous_page
              }

              edges {
                node {
                  #{select}
                }
              }
            }
          }
        QUERY

        nodes = results.fetch("edges").map { |e| e.fetch("node") }
        [results.fetch(case_correctly("page_info")), nodes]
      end
    end

    def float_of(value)
      return nil if value.nil?
      a_value_within(0.1).percent_of(value).and a_kind_of(::Float)
    end

    def int_of(value)
      return nil if value.nil?
      (a_value == value).and a_kind_of(::Integer)
    end

    def amount_aggregation(*fields, **agg_args)
      unless fields.empty?
        grouped_by = <<~EOS
          grouped_by {
            #{fields.reject { |f| f.include?(".") }.join("\n")}
            #{sub_fields("options", fields)}
            #{sub_fields("the_options", fields)}
            #{"cost { currency }" if fields.include?("cost.currency")}
          }
        EOS
      end

      <<~AGG
        widget_aggregations#{graphql_args(agg_args)} {
          edges {
            node {
              #{grouped_by}

              count

              aggregated_values {
                amount_cents {
                  approximate_sum
                  exact_sum
                  approximate_avg
                  exact_min
                  exact_max
                }

                cost {
                  amount_cents {
                    approximate_sum
                    exact_sum
                    approximate_avg
                    exact_min
                    exact_max
                  }
                }
              }
            }
          }
        }
      AGG
    end

    def all_amount_aggregations
      <<~AGG
        widget_aggregations {
          edges {
            node {
              count

              aggregated_values {
                amount_cents {
                  approximate_sum
                  exact_sum
                  approximate_avg
                  exact_min
                  exact_max
                }

                cost {
                  amount_cents {
                    approximate_sum
                    exact_sum
                    approximate_avg
                    exact_min
                    exact_max
                  }
                }
              }
            }
          }
        }
      AGG
    end

    def count_aggregation(*fields, **agg_args)
      unless fields.empty?
        grouped_by = <<~EOS
          grouped_by {
            #{fields.reject { |f| f.include?(".") }.join("\n")}
            #{sub_fields("options", fields)}
          }
        EOS
      end

      <<~AGG
        widget_aggregations#{graphql_args(agg_args)} {
          edges {
            node {
              #{grouped_by}
              count
            }
          }
        }
      AGG
    end

    def sub_fields(parent, fields)
      sub_fields = fields.filter_map { |f| f.sub("#{parent}.", "") if f.start_with?("#{parent}.") }
      return "" if sub_fields.empty?

      <<~OPTS
        #{parent} {
          #{sub_fields.join("\n")}
        }
      OPTS
    end

    def group_widgets_by_tag(allow_errors: false)
      response = call_graphql_query(<<~QUERY, allow_errors: allow_errors)
        query {
          widget_aggregations {
            nodes {
              grouped_by { tag }
              count
              aggregated_values {
                amount_cents1: amount_cents { sum: exact_sum }
                amount_cents2: amount_cents { sum: exact_sum }
              }
            }
          }
        }
      QUERY

      return response if allow_errors

      response.dig("data", case_correctly("widget_aggregations"), "nodes")
    end

    def widget_ungrouped_aggregated_values_for(field_selections)
      call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_aggregations"), "nodes", 0, case_correctly("aggregated_values"))
        query {
          widget_aggregations {
            nodes {
              aggregated_values {
                #{field_selections}
              }
            }
          }
        }
      QUERY
    end

    def group_widgets_by_fees_currency_with_approximate_distinct_value_counts
      call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_aggregations"), "nodes")
        query {
          widget_aggregations {
            nodes {
              grouped_by { fees { currency } }
              count
              aggregated_values {
                id {
                  approximate_distinct_value_count
                }
                tags {
                  approximate_distinct_value_count
                }
                amount_cents {
                  sum: exact_sum
                }
              }
            }
          }
        }
      QUERY
    end

    def group_widget_currencies_by_widget_name
      call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_currency_aggregations"), "nodes")
        query {
          widget_currency_aggregations {
            nodes {
              grouped_by { widget_name }
              count
            }
          }
        }
      QUERY
    end

    def list_widgets_with_aggregations(widget_aggregation, allow_errors: false, **query_args)
      response = call_graphql_query(<<~QUERY, allow_errors: allow_errors)
        query {
          widgets#{graphql_args(query_args)} {
            edges {
              node {
                id
                name
                amount_cents
                options {
                  size
                  color
                }

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
              }
            }
          }
          #{widget_aggregation}

          # Also query `components.widgets` (even though we do not do anything with the returned data)
          # to exercise an odd aggregations edge case where a nested relationship field exists with the
          # same name as an earlier field that had aggregations.
          components {
            edges {
              node {
                widgets {
                  edges {
                    node {
                      id
                    }
                  }
                }
              }
            }
          }
        }
      QUERY

      return response if allow_errors

      response.dig("data", case_correctly("widget_aggregations"), "edges").map { |edge| edge["node"] }
    end

    def group_components_by_position_x_and_y
      call_graphql_query(<<~QUERY).dig("data")
        query {
          by_x: component_aggregations {
            edges {
              node {
                grouped_by { position { x } }
                count
              }
            }
          }

          by_y: component_aggregations {
            edges {
              node {
                grouped_by { position { y } }
                count
              }
            }
          }
        }
      QUERY
    end
  end
end
