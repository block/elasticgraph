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
    RSpec.describe DatastoreQuery, "#search_index_expression" do
      include_context "DatastoreQueryUnitSupport"

      shared_examples_for "search index expression logic" do |timestamp_field_type|
        attr_accessor :schema_artifacts

        before(:context) do
          self.schema_artifacts = generate_schema_artifacts
        end

        it "joins the search expressions from the individual index definitions into the `index` of the search headers" do
          widgets_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
          components_def = graphql.datastore_core.index_definitions_by_name.fetch("components")

          expect(widgets_def.index_expression_for_search).to eq "widgets_rollover__*"
          expect(components_def.index_expression_for_search).to eq "components"

          query = new_query(search_index_definitions: [components_def, widgets_def])

          expect(query.search_index_expression).to eq "components,widgets_rollover__*"
        end

        context "when a rollover timestamp field is being filtered on" do
          it "avoids searching indices that come on or before a `gt` lower bound" do
            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-04-15T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "03")
          end

          it "avoids searching indices that come before a `gte` lower bound" do
            parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-04-15T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "03")

            parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-02-28T23:59:58Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01")

            parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-02-28T23:59:59.999Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01")

            parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-03-01T00:00:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02")
          end

          it "uses the higher of `gt` and `gte` when both are set, because the filter predicates are ANDed together" do
            parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-02-15T12:30:00Z", "gt" => "2021-04-01T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "03")

            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-02-15T12:30:00Z", "gte" => "2021-04-01T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "03")
          end

          it "avoids searching indices that come on or after a `lt` upper bound" do
            parts = search_index_expression_parts_for({"created_at" => {"lt" => "2021-09-15T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("10", "11", "12")
          end

          it "avoids searching indices that come after a `lte` upper bound" do
            parts = search_index_expression_parts_for({"created_at" => {"lte" => "2021-09-15T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("10", "11", "12")

            parts = search_index_expression_parts_for({"created_at" => {"lte" => "2021-11-01T00:00:01Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("12")

            parts = search_index_expression_parts_for({"created_at" => {"lte" => "2021-11-01T00:00:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("12")

            parts = search_index_expression_parts_for({"created_at" => {"lte" => "2021-10-30T23:59:59.999Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("11", "12")
          end

          it "uses the lower of `lt` and `lte` when both are set, because the filter predicates are ANDed together" do
            parts = search_index_expression_parts_for({"created_at" => {"lte" => "2021-10-01T12:30:00Z", "lt" => "2021-08-15T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("09", "10", "11", "12")

            parts = search_index_expression_parts_for({"created_at" => {"lt" => "2021-10-01T12:30:00Z", "lte" => "2021-08-15T12:30:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("09", "10", "11", "12")
          end

          it "excludes indices not targeted by a filter that has both an upper and lower bound" do
            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-03-01T00:00:00Z", "lt" => "2021-08-15T12:30:00Z"}})

            expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "09", "10", "11", "12")
          end

          it "puts the excluded indices after the included ones because the datastore returns errors if exclusions are listed first" do
            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-03-15T12:30:00Z"}})

            expect(parts).to eq(["widgets_rollover__*", "-widgets_rollover__2021-01", "-widgets_rollover__2021-02"])
              # Note: we don't care about the order of the excluded indices so we use an `or` here to allow them in either order.
              .or eq(["widgets_rollover__*", "-widgets_rollover__2021-02", "-widgets_rollover__2021-01"])
          end

          it "ANDs together multiple filter hashes when determining what indices to exclude" do
            parts = search_index_expression_parts_for([
              {"created_at" => {"gt" => "2021-03-01T00:00:00Z"}},
              {"created_at" => {"lt" => "2021-10-01T00:00:00Z"}}
            ])

            expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "10", "11", "12")
          end

          it "ignores filter operators it does not understand" do
            # greater_than isn't an understood filter operator. While this shouldn't get in to this logic,
            # if it did we should just ignore it.
            parts = search_index_expression_parts_for({"created_at" => {"greater_than" => "2021-03-01T12:30:00Z"}})

            expect(parts).to target_all_widget_indices
          end

          it "searches no indices when the time range filter excludes all timestamps" do
            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-10-01T00:00:00Z", "lt" => "2021-01-01T00:00:00Z"}})

            expect(parts).to eq []
          end

          it "supports nested timestamp fields" do
            self.schema_artifacts = generate_schema_artifacts(timestamp_field: "foo.bar.created_at")
            parts = search_index_expression_parts_for({"foo" => {"bar" => {"created_at" => {"gt" => "2021-04-15T12:30:00Z"}}}})

            expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "03")
          end

          context "when `equal_to_any_of` is used" do
            it "excludes all indices that the `equal_to_any_of` timestamps do not fall in" do
              parts = search_index_expression_parts_for({"created_at" => {"equal_to_any_of" => [
                "2021-01-15T12:30:00Z",
                "2021-03-31T23:59:59.999Z",
                "2021-05-15T12:30:00Z",
                "2021-05-30T12:30:00Z",
                "2021-07-15T12:30:00Z",
                "2021-09-15T12:30:00Z",
                "2021-11-01T00:00:00Z"
              ]}})

              expect(parts).to target_widget_indices_excluding_2021_months("02", "04", "06", "08", "10", "12")
            end

            it "is ANDed together with other predicates when selecting which indices to exclude" do
              parts = search_index_expression_parts_for({"created_at" => {
                "gte" => "2021-03-01T00:00:00Z", "gt" => "2021-04-01T00:00:00Z", # reduces to > 2021-04-01
                "lt" => "2021-08-01T00:00:00Z", "lte" => "2021-09-15T00:00:00Z", # reduces to < 2021-08-01
                "equal_to_any_of" => [
                  "2021-01-15T12:30:00Z",
                  "2021-03-31T23:59:59.999Z",
                  "2021-05-15T12:30:00Z",
                  "2021-05-30T12:30:00Z",
                  "2021-07-15T12:30:00Z",
                  "2021-09-15T12:30:00Z",
                  "2021-11-01T00:00:00Z"
                ]
              }})

              expect(parts).to target_widget_indices_excluding_all_2021_months_except("05", "07")
            end

            it "searches no indices when `equal_to_any_of` ONLY contains `[nil]`" do
              parts = search_index_expression_parts_for({"created_at" => {"equal_to_any_of" => [nil]}})

              expect(parts).to eq []
            end

            it "treats `nil` when `equal_to_any_of` includes `nil` with other timestamps as `true`" do
              parts = search_index_expression_parts_for({"created_at" => {"equal_to_any_of" => [
                "2021-01-15T12:30:00Z",
                nil,
                "2021-03-31T23:59:59.999Z"
              ]}})

              expect(parts).to target_widget_indices_excluding_all_2021_months_except("01", "03")
            end
          end

          context "when `time_of_day` filtering is used" do
            it "targets all indices since it filters only on the time but rollover uses full DateTime values" do
              parts = search_index_expression_parts_for({"created_at" => {
                "time_of_day" => {"gt" => "12:30:00Z"}
              }})

              expect(parts).to target_all_widget_indices
            end

            it "targets all indices when it is negated since matching documents could live in any index" do
              parts = search_index_expression_parts_for({"created_at" => {
                "not" => {"time_of_day" => {"gt" => "12:30:00Z"}}
              }})

              expect(parts).to target_all_widget_indices

              parts = search_index_expression_parts_for({"not" => {
                "created_at" => {"time_of_day" => {"gt" => "12:30:00Z"}}
              }})

              expect(parts).to target_all_widget_indices
            end
          end

          context "when `not` is used" do
            it "excludes indices targeted by a filter without both an upper and lower bound" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "gte" => "2021-03-01T00:00:00Z",
                "lt" => "2021-06-01T00:00:00Z"
              }}})

              expect(parts).to target_widget_indices_excluding_2021_months("03", "04", "05")
            end

            it "excludes the index containing the month the time range start in when at the beginning of the month" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "gte" => "2021-03-01T00:00:00Z"
              }}})

              expect(parts).to target_widget_indices_excluding_all_2021_months_except("01", "02")
            end

            it "includes the index containing the month the time range starts when after the beginning of the month" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "gt" => "2021-03-15T23:59:58Z"
              }}})

              expect(parts).to target_widget_indices_excluding_all_2021_months_except("01", "02", "03")
            end

            it "correctly excludes months outside of the given time ranges when using `any_of`" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "any_of" => [
                  {"lt" => "2021-01-01T00:00:00Z"},
                  {"gte" => "2021-03-01T00:00:00Z"}
                ]
              }}})

              expect(parts).to target_widget_indices_excluding_all_2021_months_except("01", "02")
            end

            it "returns all indices when `equal_to_any_of` are individual timestamps" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "equal_to_any_of" => [
                  "2021-01-15T12:30:00Z",
                  "2021-03-31T23:59:59.999Z",
                  "2021-05-15T12:30:00Z",
                  "2021-07-15T12:30:00Z"
                ]
              }}})

              expect(parts).to target_all_widget_indices
            end

            it "returns all indices when `equal_to_any_of` includes `nil` with individual timestamps" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "equal_to_any_of" => [
                  "2021-01-15T12:30:00Z",
                  "2021-03-31T23:59:59.999Z",
                  nil,
                  "2021-05-15T12:30:00Z",
                  "2021-07-15T12:30:00Z"
                ]
              }}})

              expect(parts).to target_all_widget_indices
            end

            it "returns all indices when `equal_to_any_of` is `[nil]`" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {"equal_to_any_of" => [nil]}}})

              expect(parts).to target_all_widget_indices
            end

            it "is ANDed together with other predicates when selecting which indices to exclude" do
              parts = search_index_expression_parts_for({"created_at" => {
                "gte" => "2021-03-01T00:00:00Z",
                "lt" => "2021-08-01T00:00:00Z",
                "not" => {
                  "any_of" => [
                    {"lt" => "2021-04-01T00:00:00Z"},
                    {"gte" => "2021-05-01T00:00:00Z"}
                  ]
                }
              }})

              expect(parts).to target_widget_indices_excluding_all_2021_months_except("04")
            end

            it "can handle nested `not`s" do
              nested_once = search_index_expression_parts_for({"created_at" => {"not" => {"not" => {
                "gte" => "2021-03-01T00:00:00Z"
              }}}})

              nested_twice = search_index_expression_parts_for({"created_at" => {"not" => {"not" => {"not" => {
                "gte" => "2021-03-01T00:00:00Z"
              }}}}})

              expect(nested_once).to target_widget_indices_excluding_2021_months("01", "02")
              expect(nested_twice).to target_widget_indices_excluding_all_2021_months_except("01", "02")
            end

            it "can handle `any_of` between nested `not`s" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "any_of" => [
                  {
                    "not" => {
                      "gte" => "2021-03-01T00:00:00Z",
                      "lt" => "2021-08-01T00:00:00Z"
                    }
                  },
                  {
                    "gte" => "2021-07-01T00:00:00Z"
                  }
                ]
              }}})

              expect(parts).to target_widget_indices_excluding_all_2021_months_except("03", "04", "05", "06")
            end

            it "searches all indices when the time range filter matches all timestamps" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "lt" => "2021-03-01T00:00:00Z",
                "gte" => "2021-06-01T00:00:00Z"
              }}})

              expect(parts).to target_all_widget_indices
            end

            it "searches no indices when the time range filter excludes all timestamps" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => {
                "any_of" => [
                  {"gte" => "2021-01-01T00:00:00Z"},
                  {"lt" => "2021-01-01T00:00:00Z"}
                ]
              }}})

              expect(parts).to eq []
            end

            it "searches all indices when set to nil" do
              parts = search_index_expression_parts_for({"created_at" => {"not" => nil}})

              expect(parts).to target_all_widget_indices
            end
          end

          %w[equal_to_any_of gt gte lt lte any_of].each do |operator|
            it "treats a `nil` value for a `#{operator}` filter as `true`" do
              parts = search_index_expression_parts_for({"created_at" => {operator => nil}})

              expect(parts).to target_all_widget_indices
            end
          end

          context "when `any_of` is used" do
            it "ORs together the date filter criteria from the `any_of` subfilters when determining what indices to exclude" do
              parts1 = search_index_expression_parts_for({"any_of" => [
                {"created_at" => {"lt" => "2021-03-01T00:00:00Z"}},
                {"created_at" => {"gt" => "2021-08-15T12:30:00Z"}}
              ]})

              # Order of subfilters shouldn't matter
              parts2 = search_index_expression_parts_for({"any_of" => [
                {"created_at" => {"gt" => "2021-08-15T12:30:00Z"}},
                {"created_at" => {"lt" => "2021-03-01T00:00:00Z"}}
              ]})

              # It shouldn't matter if the any_of is nested or on the outside.
              parts3 = search_index_expression_parts_for({"created_at" => {"any_of" => [
                {"lt" => "2021-03-01T00:00:00Z"},
                {"gt" => "2021-08-15T12:30:00Z"}
              ]}})

              expect(parts1).to eq(parts2).and eq(parts3).and target_widget_indices_excluding_2021_months("03", "04", "05", "06", "07")
            end

            it "excludes no indices when one of the `any_of` subfilters does not filter on the timestamp field at all" do
              parts = search_index_expression_parts_for({"any_of" => [
                {"created_at" => {"lt" => "2021-03-01T00:00:00Z"}},
                {"created_at" => {"gt" => "2021-08-15T12:30:00Z"}},
                {"id" => {"equal_to_any_of" => "some-id"}}
              ]})

              expect(parts).to target_all_widget_indices
            end

            it "excludes all indices when we have an `any_of: []` filter because that will match no results" do
              parts = search_index_expression_parts_for({"any_of" => []})

              expect(parts).to target_no_indices
            end

            it "excludes all indices when we have an `any_of: [{anyof: []}]` filter because that will match no results" do
              parts = search_index_expression_parts_for({"any_of" => [{"any_of" => []}]})

              expect(parts).to target_no_indices
            end

            it "excludes no indices when we have an `any_of: [{field: nil}]` filter because that will match all results" do
              parts = search_index_expression_parts_for({"any_of" => [{"created_at" => nil}]})

              expect(parts).to target_all_widget_indices
            end

            it "excludes no indices when we have an `any_of: [{field: nil}, {...}]` filter because that will match all results" do
              parts = search_index_expression_parts_for({"any_of" => [{"created_at" => nil}, {"id" => {"equal_to_any_of" => "some-id"}}]})

              expect(parts).to target_all_widget_indices
            end
          end

          context "for a query that includes aggregations" do
            it "filters out indices just like a non-aggregations query" do
              parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-04-15T12:30:00Z"}})
              expect(parts).to target_widget_indices_excluding_2021_months("01", "02", "03")

              parts = search_index_expression_parts_for({"created_at" => {"lte" => "2021-09-15T12:30:00Z"}})
              expect(parts).to target_widget_indices_excluding_2021_months("10", "11", "12")
            end

            it "searches exactly one index when the time range filter excludes all documents, to ensure a consistent aggregations response" do
              parts = search_index_expression_parts_for({"created_at" => {"equal_to_any_of" => []}})

              expect(parts).to contain_exactly("widgets_rollover__2021-01")
            end

            it "excludes all but one index when the time range filter excludes all known indices, to ensure a consistent aggregations response" do
              parts = search_index_expression_parts_for({"created_at" => {"gte" => "2022-04-15T12:30:00Z"}})

              expect(parts).to target_widget_indices_excluding_2021_months(
                "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"
              )
            end

            def search_index_expression_parts_for(filter_or_filters)
              aggregations = {"aggs" => aggregation_query_of(
                name: "aggs",
                groupings: [date_histogram_grouping_of("created_at", "month")]
              )}

              super(filter_or_filters, aggregations: aggregations)
            end
          end
        end

        def search_index_expression_parts_for(filter_or_filters, aggregations: {})
          filter_or_filters = coerce_date_times_in(filter_or_filters)

          allow(datastore_client).to receive(:list_indices_matching).with("widgets_rollover__*").and_return(
            # Materialize monthly indices for all of 2021.
            ("01".."12").map { |month| "widgets_rollover__2021-#{month}" }
          )

          graphql = build_graphql(
            clients_by_name: {"main" => datastore_client},
            schema_artifacts: schema_artifacts,
            # Clear our normal index settings for `widgets` since that defines indices based
            # on yearly rollover but in these tests we use monthly rollover to have a bit finer
            # granularity to work with.
            index_definitions: {"widgets" => config_index_def_of}
          )

          options = if filter_or_filters.is_a?(Array)
            {filters: filter_or_filters}
          else
            {filters: [filter_or_filters].compact}
          end

          index_def = graphql.datastore_core.index_definitions_by_name.fetch("widgets")
          builder.new_query(search_index_definitions: [index_def], aggregations: aggregations, **options).search_index_expression.split(",")
        end

        def target_all_widget_indices
          contain_exactly("widgets_rollover__*")
        end

        def target_no_indices
          eq []
        end

        def target_widget_indices_excluding_2021_months(*month_num_strings)
          indices_to_exclude = month_num_strings.map { |month| "-widgets_rollover__2021-#{month}" }
          contain_exactly("widgets_rollover__*", *indices_to_exclude)
        end

        def target_widget_indices_excluding_all_2021_months_except(*month_num_strings)
          exclusion_months = ("01".."12").to_set - month_num_strings
          target_widget_indices_excluding_2021_months(*exclusion_months)
        end

        define_method :generate_schema_artifacts do |timestamp_field: "created_at"|
          super() do |schema|
            schema.object_type "Foo" do |t|
              t.field "bar", "Bar"
            end

            schema.object_type "Bar" do |t|
              t.field "created_at", timestamp_field_type
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID!"

              if timestamp_field.start_with?("foo.")
                t.field "foo", "Foo" # for the nested case
              else
                t.field timestamp_field, timestamp_field_type
              end

              t.index "widgets" do |i|
                i.rollover :monthly, timestamp_field
              end
            end
          end
        end
      end

      context "when the timestamp field is a `DateTime`" do
        include_examples "search index expression logic", "DateTime" do
          it "avoids searching an index when filtering on a timestamp `gt` the last ms of the index" do
            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-02-28T23:59:59.999Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02")

            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-02-28T23:59:59.998Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01")
          end

          it "avoids searching an index when filtering on a timestamp `lt` the first ms of the index" do
            parts = search_index_expression_parts_for({"created_at" => {"lt" => "2021-11-01T00:00:00.001Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("12")

            parts = search_index_expression_parts_for({"created_at" => {"lt" => "2021-11-01T00:00:00Z"}})
            expect(parts).to target_widget_indices_excluding_2021_months("11", "12")
          end

          it "supports non-UTC timestamps" do
            parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-02-28T15:59:59.999-08:00"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01")

            parts = search_index_expression_parts_for({"created_at" => {"gte" => "2021-02-28T16:00:00-08:00"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02")
          end

          def coerce_date_times_in(object)
            # No coercion necessary for DateTime objects.
            object
          end
        end
      end

      context "when the timestamp field is a `Date`" do
        include_examples "search index expression logic", "Date" do
          it "avoids searching an index when filtering on a date `gt` the last day of the index" do
            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-02-28"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01", "02")

            parts = search_index_expression_parts_for({"created_at" => {"gt" => "2021-02-27"}})
            expect(parts).to target_widget_indices_excluding_2021_months("01")
          end

          it "avoids searching an index when filtering on a date `lt` the first day of the index" do
            parts = search_index_expression_parts_for({"created_at" => {"lt" => "2021-11-02"}})
            expect(parts).to target_widget_indices_excluding_2021_months("12")

            parts = search_index_expression_parts_for({"created_at" => {"lt" => "2021-11-01"}})
            expect(parts).to target_widget_indices_excluding_2021_months("11", "12")
          end

          def coerce_date_times_in(object)
            case object
            when ::Hash
              object.transform_values { |value| coerce_date_times_in(value) }
            when ::Array
              object.map { |item| coerce_date_times_in(item) }
            when /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
              object.split("T").first
            else
              object
            end
          end
        end
      end
    end
  end
end
