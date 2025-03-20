# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "elasticgraph_graphql_acceptance_support"

module ElasticGraph
  RSpec.describe "ElasticGraph::GraphQL--GraphQL types" do
    include_context "ElasticGraph GraphQL acceptance support"

    with_both_casing_forms do
      let(:page_info) { case_correctly("page_info") }
      let(:grouped_by) { case_correctly("grouped_by") }
      let(:aggregated_values) { case_correctly("aggregated_values") }
      let(:amount_cents) { case_correctly("amount_cents") }

      it "accepts and returns arbitrary JSON for `Untyped` scalar fields" do
        index_records(
          _widget1 = build(:widget, metadata: 9),
          _widget2 = build(:widget, metadata: 3.75),
          _widget3 = build(:widget, metadata: true),
          _widget4 = build(:widget, metadata: "abc"),
          _widget5 = build(:widget, metadata: ["1", 3]),
          widget6 = build(:widget, metadata: {"json" => "object", "nested" => [{"stuff" => 3}]}),
          _widget7 = build(:widget, metadata: "abc"),
          _widget8 = build(:widget, metadata: nil)
        )

        # Verify that the Untypeds all round-trip through their indexing as expected.
        # Also, verify that we can sort ascending by a Untyped field.
        widgets = list_widgets_with(:metadata, order_by: [:metadata_ASC])
        expect(widgets.map { |w| w.fetch("metadata") }).to eq([nil] + sorted_metadata = [
          "abc",
          "abc",
          3.75,
          9,
          ["1", 3],
          true,
          {"json" => "object", "nested" => [{"stuff" => 3}]}
        ])

        # Verify that we can sort DESC by a Untyped field.
        widgets = list_widgets_with(:metadata, order_by: [:metadata_DESC])
        expect(widgets.map { |w| w.fetch("metadata") }).to eq(sorted_metadata.reverse + [nil])

        # Demonstrate basic filtering on a Untyped field
        widgets = list_widgets_with(:metadata, filter: {"metadata" => {"equal_to_any_of" => [true, ["1", 3], nil]}})
        expect(widgets.map { |w| w.fetch("metadata") }).to contain_exactly(
          true,
          ["1", 3],
          nil
        )

        # Demonstrate that the equality semantics of Untyped are what we expect. Two objects with the same entries
        # but keys in a different order should be considered equal.
        widgets1 = list_widgets_with(:metadata, filter: {"metadata" => {"equal_to_any_of" => [{"json" => "object", "nested" => [{"stuff" => 3}]}]}})
        widgets2 = list_widgets_with(:metadata, filter: {"metadata" => {"equal_to_any_of" => [{"nested" => [{"stuff" => 3}], "json" => "object"}]}})
        expect(widgets1).to eq(widgets2).and eq([string_hash_of(widget6, :id, :metadata)])

        aggregations = list_widgets_with_aggregations(count_aggregation("metadata"))
        expect(aggregations).to contain_exactly(
          {grouped_by => {"metadata" => "abc"}, "count" => 2},
          {grouped_by => {"metadata" => 3.75}, "count" => 1},
          {grouped_by => {"metadata" => 9}, "count" => 1},
          {grouped_by => {"metadata" => ["1", 3]}, "count" => 1},
          {grouped_by => {"metadata" => true}, "count" => 1},
          {grouped_by => {"metadata" => {"json" => "object", "nested" => [{"stuff" => 3}]}}, "count" => 1},
          {grouped_by => {"metadata" => nil}, "count" => 1}
        )
      end

      it "supports __typename at all levels of `{Type}Connection`" do
        index_records(
          build(:widget, amount_cents: 100, options: build(:widget_options, size: "SMALL", color: "BLUE"), created_at: "2019-06-01T12:00:00Z")
        )
        results = list_widgets_and_aggregations_with_typename

        expect(results["__typename"]).to eq "Query"

        widgets = results.fetch("widgets")
        expect(widgets["__typename"]).to eq(apply_derived_type_customizations("WidgetConnection"))
        expect(widgets.dig("edges", 0, "__typename")).to eq(apply_derived_type_customizations("WidgetEdge"))
        expect(widgets.dig("edges", 0, "node", "__typename")).to eq("Widget")
        expect(widgets.dig("edges", 0, "node", "options", "__typename")).to eq("WidgetOptions")
        expect(widgets.dig("edges", 0, "node", "inventor", "__typename")).to eq("Company").or eq("Person")
        expect(widgets.dig(page_info, "__typename")).to eq("PageInfo")

        widget_aggregations = results.fetch(case_correctly("widget_aggregations"))
        expect(widget_aggregations.dig("__typename")).to eq(apply_derived_type_customizations("WidgetAggregationConnection"))
        expect(widget_aggregations.dig(page_info, "__typename")).to eq("PageInfo")
        expect(widget_aggregations.dig("edges", 0, "__typename")).to eq(apply_derived_type_customizations("WidgetAggregationEdge"))
        expect(widget_aggregations.dig("edges", 0, "node", "__typename")).to eq(apply_derived_type_customizations("WidgetAggregation"))
        expect(widget_aggregations.dig("edges", 0, "node", grouped_by, "__typename")).to eq(apply_derived_type_customizations("WidgetGroupedBy"))
        expect(widget_aggregations.dig("edges", 0, "node", grouped_by, "cost", "__typename")).to eq(apply_derived_type_customizations("MoneyGroupedBy"))
        expect(widget_aggregations.dig("edges", 0, "node", aggregated_values, "__typename")).to eq(apply_derived_type_customizations("WidgetAggregatedValues"))
        expect(widget_aggregations.dig("edges", 0, "node", aggregated_values, "cost", "__typename")).to eq(apply_derived_type_customizations("MoneyAggregatedValues"))
        expect(widget_aggregations.dig("edges", 0, "node", aggregated_values, "cost", amount_cents, "__typename")).to eq(apply_derived_type_customizations("IntAggregatedValues"))
      end

      it "supports storing and querying JsonSafeLong and LongString values" do
        large_test_value = 2**62

        original_widgets = [
          widget1 = build(:widget, weight_in_ng: 100, weight_in_ng_str: 100),
          widget2 = build(:widget, weight_in_ng: 2**30, weight_in_ng_str: 2**30),
          # The sum of these last 2 will exceed the max for the field type, allowing us to test `exact_sum` vs `approximate_sum`.
          widget3 = build(:widget, weight_in_ng: 2**52, weight_in_ng_str: large_test_value),
          widget4 = build(:widget, weight_in_ng: (2**52) + 10, weight_in_ng_str: (large_test_value + 10))
        ]

        index_records(*original_widgets)

        # Demonstrate that LongString fields allow larger values than JsonSafeLong fields.
        expect {
          index_records(build(:widget, weight_in_ng: large_test_value))
        }.to raise_error(Indexer::IndexingFailuresError, /maximum/)

        # Sort by JsonSafeLong field ASC
        widgets = list_widgets_with(:weight_in_ng,
          filter: {id: {equal_to_any_of: [widget1.fetch(:id), widget2.fetch(:id)]}},
          order_by: [:weight_in_ng_ASC])
        expect(widgets).to match([
          string_hash_of(widget1, :id, :weight_in_ng),
          string_hash_of(widget2, :id, :weight_in_ng)
        ])

        # Filter by JsonSafeLong field
        widgets = list_widgets_with(:weight_in_ng,
          filter: {weight_in_ng: {gt: 2**35}},
          order_by: [:weight_in_ng_ASC])
        expect(widgets).to match([
          string_hash_of(widget3, :id, :weight_in_ng),
          string_hash_of(widget4, :id, :weight_in_ng)
        ])

        expect {
          # Attempting to filter with a JsonSafeLong that is too large should return an error
          response = query_widgets_with(:weight_in_ng,
            allow_errors: true,
            filter: {weight_in_ng: {gt: JSON_SAFE_LONG_MAX + 1}},
            order_by: [:weight_in_ng_ASC])
          expect_error_related_to(response, apply_derived_type_customizations("JsonSafeLongFilterInput"), "gt", case_correctly("weight_in_ng"))
        }.to log(a_string_including(apply_derived_type_customizations("JsonSafeLongFilterInput"), "gt", case_correctly("weight_in_ng")))

        # Sort by JsonSafeLong field DESC
        widgets = list_widgets_with(:weight_in_ng, order_by: [:weight_in_ng_DESC])
        expect(widgets).to match([
          string_hash_of(widget4, :id, :weight_in_ng),
          string_hash_of(widget3, :id, :weight_in_ng),
          string_hash_of(widget2, :id, :weight_in_ng),
          string_hash_of(widget1, :id, :weight_in_ng)
        ])

        # Sort by LongString field ASC
        widgets = list_widgets_with(:weight_in_ng_str,
          filter: {id: {equal_to_any_of: [widget1.fetch(:id), widget2.fetch(:id)]}},
          order_by: [:weight_in_ng_str_ASC])
        expect(widgets).to match([
          string_hash_of(widget1, :id, weight_in_ng_str: "100"),
          string_hash_of(widget2, :id, weight_in_ng_str: (2**30).to_s)
        ])

        # Filter by LongString field, passing a string value
        long_string_filter_value = 2**35
        widgets = list_widgets_with(:weight_in_ng_str,
          filter: {weight_in_ng_str: {gt: long_string_filter_value.to_s}},
          order_by: [:weight_in_ng_str_ASC])
        expect(widgets).to match([
          string_hash_of(widget3, :id, weight_in_ng_str: large_test_value.to_s),
          string_hash_of(widget4, :id, weight_in_ng_str: (large_test_value + 10).to_s)
        ])

        # Attempting to filter with a LongString value that is too large should return an error
        response = query_widgets_with(:weight_in_ng_str,
          allow_errors: true,
          filter: {weight_in_ng_str: {gt: LONG_STRING_MAX + 1}},
          order_by: [:weight_in_ng_str_ASC])
        expect_error_related_to(response, "LongString", "gt", case_correctly("weight_in_ng_str"))

        # Sort by JsonSafeLong field DESC
        widgets = list_widgets_with(:weight_in_ng_str, order_by: [:weight_in_ng_str_DESC])
        expect(widgets).to match([
          string_hash_of(widget4, :id, weight_in_ng_str: (large_test_value + 10).to_s),
          string_hash_of(widget3, :id, weight_in_ng_str: large_test_value.to_s),
          string_hash_of(widget2, :id, weight_in_ng_str: (2**30).to_s),
          string_hash_of(widget1, :id, weight_in_ng_str: "100")
        ])

        # Aggregate over all widgets. The sum should exceed the maximums for the scalar field type.
        # This should make `exact_sum` nil.
        aggregations = list_widgets_with_aggregations(all_weight_in_ng_aggregations)
        weight_in_ngs = original_widgets.map { |w| w.fetch(case_correctly("weight_in_ng").to_sym) }
        weight_in_ng_strs = original_widgets.map { |w| w.fetch(case_correctly("weight_in_ng_str").to_sym).to_i }
        expect(aggregations.size).to eq(1)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "approximate_sum")).to be_approximately(weight_in_ngs.sum)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_sum")).to be_approximately(weight_in_ng_strs.sum)
        # Value exceeds max JsonSafeLong, so exact_sum should be nil
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "exact_sum")).to be nil
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "exact_sum")).to be nil
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "approximate_avg")).to be_a(::Float).and be_approximately(weight_in_ngs.sum / weight_in_ngs.size)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_avg")).to be_a(::Float).and be_approximately(weight_in_ng_strs.sum / weight_in_ng_strs.size)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "exact_min")).to be_a(::Integer).and eq(weight_in_ngs.min)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "exact_min")).to be_a(::Integer).and eq(weight_in_ng_strs.min)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_min")).to be_a(::String).and eq(weight_in_ng_strs.min.to_s)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "exact_max")).to be_a(::Integer).and eq(weight_in_ngs.max)
        # Max value of `weight_in_ng_str` exceeds `JsonSafeLong` range, so exact should be nil but approx should be available.
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "exact_max")).to be nil # the max exceeds the JsonSafeLong range, so we can't get it exact
        weight_in_ng_str_approx_max = value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_max")
        expect(weight_in_ng_str_approx_max).to be_a(::String)
        expect(weight_in_ng_str_approx_max.to_f).to be_approximately(weight_in_ng_strs.max)

        # Aggregate over only the first two widgets (excluding the last 2, to ensure that the sum stays under the JsonSafeLong max)
        # This should make `exact_sum` non-nil.
        aggregations = list_widgets_with_aggregations(
          all_weight_in_ng_aggregations(filter: {weight_in_ng_str: {lt: large_test_value.to_s}})
        )
        weight_in_ngs = weight_in_ngs.first(2) # drop last 2 weights
        weight_in_ng_strs = weight_in_ng_strs.first(2) # drop last 2 weights
        expect(aggregations.size).to eq(1)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "approximate_sum")).to be_approximately(weight_in_ngs.sum)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_sum")).to be_approximately(weight_in_ng_strs.sum)
        # Value does not exceed max JsonSafeLong, so exact_sum should be present
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "exact_sum")).to be_a(::Integer).and eq(weight_in_ngs.sum)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "exact_sum")).to be_a(::Integer).and eq(weight_in_ng_strs.sum)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "approximate_avg")).to be_a(::Float).and be_approximately(weight_in_ngs.sum / weight_in_ngs.size)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_avg")).to be_a(::Float).and be_approximately(weight_in_ng_strs.sum / weight_in_ng_strs.size)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "exact_min")).to be_a(::Integer).and eq(weight_in_ngs.min)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "exact_min")).to be_a(::Integer).and eq(weight_in_ng_strs.min)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_min")).to be_a(::String).and eq(weight_in_ng_strs.min.to_s)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng", "exact_max")).to be_a(::Integer).and eq(weight_in_ngs.max)
        # Value does not exceed max JsonSafeLong, so approximate_max should be present
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "exact_max")).to be_a(::Integer).and eq(weight_in_ng_strs.max)
        expect(value_at_path(aggregations.first, aggregated_values, "weight_in_ng_str", "approximate_max")).to be_a(::String).and eq(weight_in_ng_strs.max.to_s)
      end

      it "supports storing and querying GeoLocation values" do
        index_records(
          build(:address, full_address: "space-needle", geo_location: {latitude: 47.62089914996321, longitude: -122.34924708967479}),
          build(:address, full_address: "crystal-mtn", geo_location: {latitude: 46.93703464703253, longitude: -121.47398616597955}),
          build(:address, full_address: "pike-place-mkt", geo_location: {latitude: 47.60909792583577, longitude: -122.33981115022492})
        )

        # Fetch geo_location values.
        addresses = list_addresses(
          fields: "full_address geo_location { latitude longitude }",
          order_by: [:full_address_ASC]
        )

        expect(addresses).to eq [
          {case_correctly("full_address") => "crystal-mtn", case_correctly("geo_location") => {"latitude" => 46.93703464703253, "longitude" => -121.47398616597955}},
          {case_correctly("full_address") => "pike-place-mkt", case_correctly("geo_location") => {"latitude" => 47.60909792583577, "longitude" => -122.33981115022492}},
          {case_correctly("full_address") => "space-needle", case_correctly("geo_location") => {"latitude" => 47.62089914996321, "longitude" => -122.34924708967479}}
        ]

        downtown_seattle_location = {"latitude" => 47.6078024243176, "longitude" => -122.3345525727595}

        # Filtering on distance.
        addresses = list_addresses(
          fields: "full_address",
          filter: {"geo_location" => {"near" => downtown_seattle_location.merge({"max_distance" => 3, "unit" => :MILE})}},
          order_by: [:full_address_ASC]
        )

        # Crystal Mountain is not within 3 miles of downtown Seattle but Pike Place Market and the Space Needle are.
        expect(addresses).to eq [
          {case_correctly("full_address") => "pike-place-mkt"},
          {case_correctly("full_address") => "space-needle"}
        ]

        # For now, other features (e,g. sorting and aggregating) are not supported on GeoLocation values.
      end
    end

    def value_at_path(hash, *field_parts)
      field_parts = field_parts.map { |f| case_correctly(f) }
      hash.dig(*field_parts)
    end

    def be_approximately(value)
      be_a(::Float).and be_within(0.00001).percent_of(value)
    end

    def list_widgets_and_aggregations_with_typename
      call_graphql_query(<<~QUERY).dig("data")
        query {
          __typename

          widgets {
            __typename
            edges {
              __typename
              node {
                __typename
                id
                options {
                  __typename
                  size
                }
                inventor {
                  __typename

                  ...on Person {
                    nationality
                  }

                  ...on Company {
                    stock_ticker
                  }
                }
              }
            }
            page_info {
              __typename
            }
          }

          widget_aggregations {
            __typename
            page_info {
              __typename
            }
            edges {
              __typename
              node {
                __typename

                grouped_by {
                  __typename

                  cost {
                    currency
                    __typename
                  }
                }

                aggregated_values {
                  __typename

                  cost {
                    __typename
                    amount_cents {
                      __typename
                      approximate_sum
                    }
                  }
                }
              }
            }
          }
        }
      QUERY
    end

    def all_weight_in_ng_aggregations(**agg_args)
      <<~AGG
        widget_aggregations#{graphql_args(agg_args)} {
          edges {
            node {
              count

              aggregated_values {
                weight_in_ng {
                  approximate_sum
                  exact_sum
                  approximate_avg
                  exact_min
                  exact_max
                }

                weight_in_ng_str {
                  approximate_sum
                  exact_sum
                  approximate_avg
                  exact_min
                  approximate_min
                  exact_max
                  approximate_max
                }
              }
            }
          }
        }
      AGG
    end

    def count_aggregation(*fields, **agg_args)
      <<~AGG
        widget_aggregations#{graphql_args(agg_args)} {
          edges {
            node {
              grouped_by {
                #{fields.join("\n")}
              }
              count
            }
          }
        }
      AGG
    end

    def list_widgets_with_aggregations(widget_aggregations, **query_args)
      call_graphql_query(<<~QUERY).dig("data", case_correctly("widget_aggregations"), "edges").map { |edge| edge["node"] }
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

          #{widget_aggregations}

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
    end

    def list_widgets_with(fieldname, **query_args)
      query_widgets_with(fieldname, **query_args).dig("data", "widgets", "edges").map { |we| we.fetch("node") }
    end

    def query_widgets_with(fieldname, allow_errors: false, **query_args)
      call_graphql_query(<<~QUERY, allow_errors: allow_errors)
        query {
          widgets#{graphql_args(query_args)} {
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

    def list_addresses(fields:, gql: graphql, **query_args)
      call_graphql_query(<<~QUERY, gql: gql).dig("data", "addresses", "edges").map { |we| we.fetch("node") }
        query {
          addresses#{graphql_args(query_args)} {
            edges {
              node {
                #{fields}
              }
            }
          }
        }
      QUERY
    end
  end
end
