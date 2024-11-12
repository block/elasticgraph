# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "shard routing" do
      include_context "DatastoreQueryUnitSupport"

      attr_accessor :schema_artifacts_by_route_with_field_paths

      before(:context) do
        self.schema_artifacts_by_route_with_field_paths = ::Hash.new do |hash, route_with_field_paths|
          hash[route_with_field_paths] = generate_schema_artifacts do |schema|
            schema.object_type "Foo" do |t|
              t.field "bar", "Bar"
            end

            schema.object_type "Bar" do |t|
              t.field "name", "String"
            end

            route_with_field_paths.each_with_index do |path, number|
              schema.object_type "Type#{number}" do |t|
                t.field "id", "ID"

                if path.start_with?("foo.")
                  t.field "foo", "Foo" # for the nested case
                else
                  t.field path, "ID!"
                end

                t.index "index#{number}" do |i|
                  i.route_with path
                end
              end
            end
          end
        end
      end

      it "searches all shards when the query does not filter on a single `route_with_field_paths` field" do
        expect(shard_routing_for(["name"], {})).to search_all_shards
        expect(shard_routing_for(["name"], {
          "id" => {"equal_to_any_of" => ["abc"]}
        })).to search_all_shards
      end

      it "searches the shards identified by the values in an `equal_to_any_of` filter for a single `route_with_field_paths` field" do
        expect(shard_routing_for(["name"], {
          "name" => {"equal_to_any_of" => ["abc", "def"]}
        })).to search_shards_identified_by "abc", "def"
      end

      it "ignores `nil` among other values in `equal_to_any_of` filter for a single `route_with_field_paths` field" do
        expect(shard_routing_for(["name"], {
          "name" => {"equal_to_any_of" => ["abc", nil, "def"]}
        })).to search_shards_identified_by "abc", "def"
      end

      it "searches all shards when the query filters on single `route_with_field_paths` field using an inexact operator" do
        expect(shard_routing_for(["name"], {"name" => {"gt" => "abc"}})).to search_all_shards
        expect(shard_routing_for(["name"], {"name" => {"gte" => "abc"}})).to search_all_shards
        expect(shard_routing_for(["name"], {"name" => {"lt" => "abc"}})).to search_all_shards
        expect(shard_routing_for(["name"], {"name" => {"lte" => "abc"}})).to search_all_shards
        expect(shard_routing_for(["name"], {"name" => {"matches" => "abc"}})).to search_all_shards
        expect(shard_routing_for(["name"], {"name" => {"matches_query" => {"query" => "abc"}}})).to search_all_shards
        expect(shard_routing_for(["name"], {"name" => {"matches_phrase" => {"phrase" => "abc"}}})).to search_all_shards
      end

      it "ignores inequality operators on a single `route_with_field_paths` field when that field also has an exact equality operator" do
        # the fact that we are filtering `> abc` can be ignored because we are only looking for `def` based on `equal_to_any_of`.
        expect(shard_routing_for(["name"], {"name" => {
          "gt" => "abc",
          "equal_to_any_of" => ["def"]
        }})).to search_shards_identified_by "def"

        # ordering of operators shouldn't matter...
        expect(shard_routing_for(["name"], {"name" => {
          "equal_to_any_of" => ["def"],
          "gt" => "abc"
        }})).to search_shards_identified_by "def"
      end

      it "ignores filters on other fields so long as they are not in an `any_of` clause (for multiple filters in one hash)" do
        expect(shard_routing_for(["name"], {
          "name" => {"equal_to_any_of" => ["abc", "def"]},
          "cost" => {"gt" => 10}
        })).to search_shards_identified_by "abc", "def"
      end

      it "ignores filters on other fields so long as they are not in an `any_of` clause (for multiple filters in an array of hashes)" do
        expect(shard_routing_for(["name"], [
          {"name" => {"equal_to_any_of" => ["abc", "def"]}},
          {"cost" => {"gt" => 10}}
        ])).to search_shards_identified_by "abc", "def"

        # order should not matter...
        expect(shard_routing_for(["name"], [
          {"cost" => {"gt" => 10}},
          {"name" => {"equal_to_any_of" => ["abc", "def"]}}
        ])).to search_shards_identified_by "abc", "def"
      end

      it "searches the shards identified by the set intersection of filter values when we have multiple `equal_to_any_of` filters on the same `route_with_field_paths` field" do
        expect(shard_routing_for(["name"], [
          {"name" => {"equal_to_any_of" => ["abc", "def"]}},
          {"name" => {"equal_to_any_of" => ["def", "ghi"]}}
        ])).to search_shards_identified_by "def"
      end

      context "on a query with no aggregations" do
        it "searches no shards when the result of the set intersection of filter values has no values, because no documents can match the filter" do
          expect(shard_routing_for(["name"], [
            {"name" => {"equal_to_any_of" => ["abc", "def"]}},
            {"name" => {"equal_to_any_of" => ["ghi", "jkl"]}}
          ])).to search_no_shards
        end

        it "searches no shards when the query filters with `equal_to_any_of: []` on a single `route_with_field_paths` field, because no documents can match the filter" do
          expect(shard_routing_for(["name"], {
            "name" => {"equal_to_any_of" => []}
          })).to search_no_shards
        end

        it "searches no shards when the query filters with `equal_to_any_of: [nil]` on a single `route_with_field_paths` field, because no documents can match the filter" do
          expect(shard_routing_for(["name"], {
            "name" => {"equal_to_any_of" => [nil]}
          })).to search_no_shards
        end
      end

      context "on a query with aggregations" do
        it "searches the fallback shard when the result of the set intersection of filter values has no values, because we must search a shard to get a response with the expected structure" do
          expect(shard_routing_for(["name"], [
            {"name" => {"equal_to_any_of" => ["abc", "def"]}},
            {"name" => {"equal_to_any_of" => ["ghi", "jkl"]}}
          ])).to search_the_fallback_shard
        end

        it "searches the fallback shard when the query filters with `equal_to_any_of: []` on a single `route_with_field_paths` field, because we must search a shard to get a response with the expected structure" do
          expect(shard_routing_for(["name"], {
            "name" => {"equal_to_any_of" => []}
          })).to search_the_fallback_shard
        end

        it "searches the fallback shard when the query filters with `equal_to_any_of: [nil]` on a single `route_with_field_paths` field, because we must search a shard to get a response with the expected structure" do
          expect(shard_routing_for(["name"], {
            "name" => {"equal_to_any_of" => [nil]}
          })).to search_the_fallback_shard
        end

        def shard_routing_for(route_with_field_paths, filter_or_filters)
          aggregations = [aggregation_query_of(computations: [computation_of("amountMoney", "amount", :sum)])]
          super(route_with_field_paths, filter_or_filters, aggregations: aggregations)
        end
      end

      it "searches all shards when the query filters with `equal_to_any_of: nil` on a single `route_with_field_paths` field because our current filter logic ignores that filter and we must search all shards" do
        expect(shard_routing_for(["name"], {
          "name" => {"equal_to_any_of" => nil}
        })).to search_all_shards
      end

      it "searches all shards when the query filters with `equal_to_any_on` on a single `route_with_field_paths` field only contains ignored routing values" do
        expect(shard_routing_for(
          ["name"],
          {"name" => {"equal_to_any_of" => ["ignored_value"]}},
          ignored_routing_values: ["ignored_value"]
        )).to search_all_shards
      end

      it "searches all shards when the query filters with `equal_to_any_on` on a single `route_with_field_paths` field contains both an ignored routing value and non-ignored routing values" do
        expect(shard_routing_for(
          ["name"],
          {"name" => {"equal_to_any_of" => ["ignored_value", "not_ignored_value"]}},
          ignored_routing_values: ["ignored_value"]
        )).to search_all_shards
      end

      it "supports nested field paths for routing fields" do
        filters = {"foo" => {"bar" => {"name" => {"equal_to_any_of" => ["abc", "def"]}}}}

        routing = shard_routing_for(["foo.bar.name"], filters)

        expect(routing).to search_shards_identified_by "abc", "def"
      end

      it "supports nested field paths for routing fields with `equal_to_any_of` containing `nil`" do
        filters = {"foo" => {"bar" => {"name" => {"equal_to_any_of" => ["abc", nil, "def"]}}}}

        routing = shard_routing_for(["foo.bar.name"], filters)

        expect(routing).to search_shards_identified_by "abc", "def"
      end

      it "searches all shards when there is an `any_of` filter clause that could match documents not covered by an exact value filter" do
        expect(shard_routing_for(["name"], {"any_of" => [
          {"name" => {"equal_to_any_of" => ["abc", "def"]}},
          {"cost" => {"gt" => 10}}
        ]})).to search_all_shards

        # nil value shouldn't matter
        expect(shard_routing_for(["name"], {"any_of" => [
          {"name" => {"equal_to_any_of" => ["abc", nil, "def"]}},
          {"cost" => {"gt" => 10}}
        ]})).to search_all_shards

        # order shouldn't matter...
        expect(shard_routing_for(["name"], {"any_of" => [
          {"cost" => {"gt" => 10}},
          {"name" => {"equal_to_any_of" => ["abc", "def"]}}
        ]})).to search_all_shards
      end

      it "searches the shards identified by the set union of filter values when all `any_of` clauses filter on the same `route_with_field_paths` field" do
        expect(shard_routing_for(["name"], {"any_of" => [
          {"name" => {"equal_to_any_of" => ["abc", "def"]}},
          {"name" => {"equal_to_any_of" => ["def", "ghi"]}}
        ]})).to search_shards_identified_by "abc", "def", "ghi"

        # nil value shouldn't matter
        expect(shard_routing_for(["name"], {"any_of" => [
          {"name" => {"equal_to_any_of" => ["abc", nil, "def"]}},
          {"name" => {"equal_to_any_of" => ["def", "ghi", nil]}}
        ]})).to search_shards_identified_by "abc", "def", "ghi"
      end

      it "searches all shards when one branch of an `any_of` could match documents on any shard" do
        expect(shard_routing_for(["name"], {"any_of" => [
          {"name" => {"equal_to_any_of" => ["abc", "def"]}},
          {"name" => {"equal_to_any_of" => ["def", "ghi"]}},
          {"name" => {"gt" => "xyz"}}
        ]})).to search_all_shards

        # order shouldn't matter...
        expect(shard_routing_for(["name"], {"any_of" => [
          {"name" => {"equal_to_any_of" => ["abc", "def"]}},
          {"name" => {"gt" => "xyz"}},
          {"name" => {"equal_to_any_of" => ["def", "ghi"]}}
        ]})).to search_all_shards

        expect(shard_routing_for(["name"], {"any_of" => [
          {"name" => {"gt" => "xyz"}},
          {"name" => {"equal_to_any_of" => ["abc", "def"]}},
          {"name" => {"equal_to_any_of" => ["def", "ghi"]}}
        ]})).to search_all_shards
      end

      # TODO: Change behaviour so no shards are matched when given `anyOf => []`.
      #       Updated references of ignore and prune to use language such as "treated ... as `true`"
      it "searches no shards when we have an `any_of: []` filter because that will match no results" do
        expect(shard_routing_for(["name"], {
          "any_of" => []
        })).to search_all_shards
      end

      # TODO: Change behaviour so no shards are matched when given `anyOf => {anyOf => []}`
      #       Updated references of ignore and prune to use language such as "treated ... as `true`"
      it "searches no shards when we have an `any_of: [{anyof: []}]` filter because that will match no results" do
        expect(shard_routing_for(["name"], {
          "any_of" => [{"any_of" => []}]
        })).to search_all_shards
      end

      it "searches all shards when we have an `any_of: [{field: nil}]` filter because that will match all results" do
        expect(shard_routing_for(["name"], {
          "any_of" => [{"name" => nil}]
        })).to search_all_shards
      end

      it "searches all shards when we have an `any_of: [{field: nil}, {...}]` filter because that will match all results" do
        expect(shard_routing_for(["name"], {
          "any_of" => [{"name" => nil}, {"id" => {"equal_to_any_of" => ["abc"]}}]
        })).to search_all_shards
      end

      describe "not" do
        it "searches all shards when there are values in an `equal_to_any_of` filter" do
          expect(shard_routing_for(["name"],
            {"name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}}})).to search_all_shards
        end

        it "searches the shards identified by the values in an `equal_to_any_of` filter alongside `not`" do
          expect(shard_routing_for(["name"], {"name" => {
            "not" => {"equal_to_any_of" => ["abc"]},
            "equal_to_any_of" => ["abc", "def"]
          }})).to search_shards_identified_by "def"

          # nil value shouldn't matter
          expect(shard_routing_for(["name"], {"name" => {
            "not" => {"equal_to_any_of" => ["abc", nil]},
            "equal_to_any_of" => ["abc", "def"]
          }})).to search_shards_identified_by "def"
        end

        it "searches all shards when `any_of` is an empty set" do
          expect(shard_routing_for(["name"], {
            "not" => {"any_of" => []}
          })).to search_all_shards
        end

        it "searches all shards when the query filters with `equal_to_any_of: []`" do
          expect(shard_routing_for(["name"], {
            "name" => {
              "not" => {"equal_to_any_of" => []}
            }
          })).to search_all_shards
        end

        it "searches all shards when the query filters with `equal_to_any_of: [nil]`" do
          expect(shard_routing_for(["name"], {
            "name" => {
              "not" => {"equal_to_any_of" => [nil]}
            }
          })).to search_all_shards
        end

        it "searches all shards when the query filters with `equal_to_any_of: nil`" do
          expect(shard_routing_for(["name"], {
            "name" => {
              "not" => {"equal_to_any_of" => nil}
            }
          })).to search_all_shards
        end

        it "searches all shards when set to nil`" do
          expect(shard_routing_for(["name"], {
            "name" => {"not" => nil}
          })).to search_all_shards
        end

        it "searches all shards when the query does not filter on a single `route_with_field_paths` field" do
          expect(shard_routing_for(["name"], {
            "id" => {"not" => {"equal_to_any_of" => ["abc"]}}
          })).to search_all_shards
        end

        it "searches all shards when the query filters on single `route_with_field_paths` field using an inexact operator" do
          expect(shard_routing_for(["name"], {"name" => {"not" => {"gt" => "abc"}}})).to search_all_shards
          expect(shard_routing_for(["name"], {"name" => {"not" => {"gte" => "abc"}}})).to search_all_shards
          expect(shard_routing_for(["name"], {"name" => {"not" => {"lt" => "abc"}}})).to search_all_shards
          expect(shard_routing_for(["name"], {"name" => {"not" => {"lte" => "abc"}}})).to search_all_shards
          expect(shard_routing_for(["name"], {"name" => {"not" => {"matches" => "abc"}}})).to search_all_shards
          expect(shard_routing_for(["name"], {"name" => {"not" => {"matches_query" => {"query" => "abc"}}}})).to search_all_shards
          expect(shard_routing_for(["name"], {"name" => {"not" => {"matches_phrase" => {"phrase" => "abc"}}}})).to search_all_shards
        end

        it "ignores inequality operators on a single `route_with_field_paths` field when that field also has an exact equality operator" do
          # the fact that we are filtering `!(> xyz)` can be ignored because we are only looking for `def` based on `equal_to_any_of`.
          expect(shard_routing_for(["name"], {"name" => {
            "not" => {"gt" => "xyz"},
            "equal_to_any_of" => ["def"]
          }})).to search_shards_identified_by "def"

          # ordering of operators shouldn't matter...
          expect(shard_routing_for(["name"], {"name" => {
            "equal_to_any_of" => ["def"],
            "not" => {"gt" => "xyz"}
          }})).to search_shards_identified_by "def"
        end

        it "ignores filters on other fields so long as they are not in an `any_of` clause (for multiple filters in one hash)" do
          expect(shard_routing_for(["name"], {
            "name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}},
            "cost" => {"gt" => 10}
          })).to search_all_shards
        end

        it "ignores filters on other fields so long as they are not in an `any_of` clause (for multiple filters in an array of hashes)" do
          expect(shard_routing_for(["name"], [
            {"name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}}},
            {"cost" => {"gt" => 10}}
          ])).to search_all_shards

          expect(shard_routing_for(["name"], [
            {"name" => {"not" => {"equal_to_any_of" => ["abc", nil, "def"]}}},
            {"cost" => {"gt" => 10}}
          ])).to search_all_shards

          expect(shard_routing_for(["name"], [
            {"name" => {"not" => {"equal_to_any_of" => []}}},
            {"cost" => {"gt" => 10}}
          ])).to search_all_shards

          # order should not matter...
          expect(shard_routing_for(["name"], [
            {"cost" => {"gt" => 10}},
            {"name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}}}
          ])).to search_all_shards

          expect(shard_routing_for(["name"], [
            {"cost" => {"gt" => 10}},
            {"name" => {"not" => {"equal_to_any_of" => ["abc", nil, "def"]}}}
          ])).to search_all_shards

          expect(shard_routing_for(["name"], [
            {"cost" => {"gt" => 10}},
            {"name" => {"not" => {"equal_to_any_of" => []}}}
          ])).to search_all_shards
        end

        it "searches the shards identified by the set intersection of filter values when we have multiple `equal_to_any_of` filters on the same `route_with_field_paths` field" do
          expect(shard_routing_for(["name"], [
            {"name" => {"equal_to_any_of" => ["abc", "def"]}},
            {"name" => {"not" => {"equal_to_any_of" => ["def", "ghi"]}}}
          ])).to search_shards_identified_by "abc"

          expect(shard_routing_for(["name"], [
            {"name" => {"equal_to_any_of" => ["abc", "def"]}},
            {"name" => {"not" => {"equal_to_any_of" => ["def", nil, "ghi"]}}}
          ])).to search_shards_identified_by "abc"

          expect(shard_routing_for(["name"], [
            {"name" => {"equal_to_any_of" => ["abc", nil, "def"]}},
            {"name" => {"not" => {"equal_to_any_of" => ["def", "ghi"]}}}
          ])).to search_shards_identified_by "abc"

          expect(shard_routing_for(["name"], [
            {"name" => {"equal_to_any_of" => ["abc", "def"]}},
            {"name" => {"not" => {"equal_to_any_of" => []}}}
          ])).to search_shards_identified_by "abc", "def"
        end

        it "supports nested field paths for routing fields" do
          filters = {"foo" => {"bar" => {"name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}}}}}

          routing = shard_routing_for(["foo.bar.name"], filters)

          expect(routing).to search_all_shards
        end

        it "can handle nested `not`s" do
          expect(shard_routing_for(
            ["name"],
            {"name" => {"equal_to_any_of" => ["abc", "def"]}}
          )).to search_shards_identified_by "abc", "def"

          expect(shard_routing_for(
            ["name"],
            {"name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}}}
          )).to search_all_shards

          expect(shard_routing_for(
            ["name"],
            {"not" => {"name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}}}}
          )).to search_shards_identified_by "abc", "def"

          expect(shard_routing_for(
            ["name"],
            {"not" => {"not" => {"name" => {"not" => {"equal_to_any_of" => ["abc", "def"]}}}}}
          )).to search_all_shards
        end
      end

      context "when there are multiple fields in `route_with_field_paths`" do
        it "searches all shards when the query does not filter on any of the `route_with_field_paths`" do
          expect(shard_routing_for(["name", "user_id"], {})).to search_all_shards
          expect(shard_routing_for(["name", "user_id"], {
            "id" => {"equal_to_any_of" => ["abc"]}
          })).to search_all_shards
        end

        it "searches the shards identified by the set union of filter values, provided we are filtering on all routing fields, to ensure we search all shards that may contain matching documents" do
          expect(shard_routing_for(["name", "user_id"], {
            "name" => {"equal_to_any_of" => ["abc", "def"]},
            "user_id" => {"equal_to_any_of" => ["123", "456"]}
          })).to search_shards_identified_by "abc", "def", "123", "456"
        end

        it "searches all shards when one or more of the `route_with_field_paths` is not filtered on at all, to ensure we can find documents in the index with that routing field" do
          expect(shard_routing_for(["name", "user_id"], {
            "name" => {"equal_to_any_of" => ["abc", "def"]}
          })).to search_all_shards

          expect(shard_routing_for(["name", "user_id"], {
            "user_id" => {"equal_to_any_of" => ["123", "456"]}
          })).to search_all_shards
        end

        it "works correctly when `any_of` is used by multiple cousin nodes" do
          expect(shard_routing_for(["name", "user_id"], {
            "name" => {"any_of" => [{"equal_to_any_of" => ["abc", "def"]}]},
            "user_id" => {"any_of" => [{"equal_to_any_of" => ["123", "456"]}]}
          })).to search_shards_identified_by "abc", "def", "123", "456"
        end
      end

      def shard_routing_for(route_with_field_paths, filter_or_filters, ignored_routing_values: [], aggregations: nil)
        options = if filter_or_filters.is_a?(Array)
          {filters: filter_or_filters}
        else
          {filter: filter_or_filters}
        end

        search_index_definitions = search_index_definitions_for(route_with_field_paths, ignored_routing_values)

        query = new_query(search_index_definitions: search_index_definitions, aggregations: aggregations, **options)

        datastore_msearch_header_of(query)[:routing]&.split(",").tap do |used_routing_values|
          expect(used_routing_values).to eq(query.shard_routing_values)
        end
      end

      def search_all_shards
        eq(nil) # when no routing value is provided, the datastore will search all shards
      end

      def search_shards_identified_by(*routing_values)
        contain_exactly(*routing_values)
      end

      def search_no_shards
        eq [] # when an empty set of routing values are provided, the datastore will search no shards
      end

      def search_the_fallback_shard
        eq ["fallback_shard_routing_value"]
      end

      def search_index_definitions_for(route_with_field_paths, ignored_routing_values)
        index_definitions = route_with_field_paths.length.times.map do |i|
          ["index#{i}", config_index_def_of(ignore_routing_values: ignored_routing_values)]
        end.to_h

        graphql = build_graphql(
          index_definitions: index_definitions,
          schema_artifacts: schema_artifacts_by_route_with_field_paths[route_with_field_paths]
        )

        route_with_field_paths.map.with_index do |path, number|
          graphql.datastore_core.index_definitions_by_name.fetch("index#{number}").tap do |index_def|
            expect(index_def.route_with).to eq path
          end
        end
      end

      def datastore_msearch_header_of(query)
        query.send(:to_datastore_msearch_header)
      end
    end
  end
end
