# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "datastore_query_unit_support"
require "tempfile"

module ElasticGraph
  class GraphQL
    RSpec.describe DatastoreQuery, "filtering" do
      include_context "DatastoreQueryUnitSupport"

      let(:always_false_condition) do
        {bool: {filter: Filtering::BooleanQuery::ALWAYS_FALSE_FILTER.clauses}}
      end

      it "builds a `nil` datastore body when given no filters (passed as `nil`)" do
        query = new_query(client_filter: nil)

        expect(datastore_body_of(query)).to not_filter_datastore_at_all
      end

      it "builds a `nil` datastore body when given no filters (passed as an empty hash)" do
        query = new_query(client_filter: {})

        expect(datastore_body_of(query)).to not_filter_datastore_at_all
      end

      it "ignores unknown filtering operators and logs a warning" do
        query = new_query(client_filter: {"name" => {"like" => "abc"}})

        expect {
          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        }.to log a_string_including('Ignoring unknown filtering operator (like: "abc") on field `name`')
      end

      it "ignores malformed filters and logs a warning" do
        query = new_query(client_filter: {"name" => [7]})

        expect {
          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        }.to log a_string_including("Ignoring unknown filtering operator (name: [7]) on field ``")
      end

      it "takes advantage of ids query when filtering on id" do
        query = new_query(client_filter: {"id" => {"equal_to_any_of" => ["testid"]}})

        expect(datastore_body_of(query)).to filter_datastore_with(ids: {values: ["testid"]})
      end

      it "deduplicates the `id` to a unique set of values when given duplicates in an `equal_to_any_of: [...]` filter" do
        query = new_query(client_filter: {"id" => {"equal_to_any_of" => ["a", "b", "a"]}})

        expect(datastore_body_of(query)).to filter_datastore_with(ids: {values: ["a", "b"]})
      end

      it "builds a `terms` condition when given an `equal_to_any_of: [...]` filter" do
        query = new_query(client_filter: {"age" => {"equal_to_any_of" => [25, 30]}})

        expect(datastore_body_of(query)).to filter_datastore_with(terms: {"age" => [25, 30]})
      end

      it "deduplicates the `terms` to a unique set of values when given duplicates in an `equal_to_any_of: [...]` filter" do
        query = new_query(client_filter: {"age" => {"equal_to_any_of" => [25, 30, 25]}})

        expect(datastore_body_of(query)).to filter_datastore_with(terms: {"age" => [25, 30]})
      end

      it "builds a `range` condition when given an `gt: scalar` filter" do
        query = new_query(client_filter: {"age" => {"gt" => 25}})

        expect(datastore_body_of(query)).to filter_datastore_with(range: {"age" => {gt: 25}})
      end

      it "builds a `range` condition when given an `gte: scalar` filter" do
        query = new_query(client_filter: {"age" => {"gte" => 25}})

        expect(datastore_body_of(query)).to filter_datastore_with(range: {"age" => {gte: 25}})
      end

      it "builds a `range` condition when given an `lt: scalar` filter" do
        query = new_query(client_filter: {"age" => {"lt" => 25}})

        expect(datastore_body_of(query)).to filter_datastore_with(range: {"age" => {lt: 25}})
      end

      it "builds a `range` condition when given an `lte: scalar` filter" do
        query = new_query(client_filter: {"age" => {"lte" => 25}})

        expect(datastore_body_of(query)).to filter_datastore_with(range: {"age" => {lte: 25}})
      end

      it "merges multiple `range` clauses that are on the same field" do
        query1 = new_query(client_filter: {"age" => {"gt" => 10, "lte" => 25}})
        expect(datastore_body_of(query1)).to filter_datastore_with(range: {"age" => {gt: 10, lte: 25}})

        query2 = new_query(client_filter: {"age" => {"gt" => 10, "lte" => 25, "gte" => 20, "lt" => 50}})
        expect(datastore_body_of(query2)).to filter_datastore_with(range: {"age" => {gt: 10, gte: 20, lt: 50, lte: 25}})
      end

      it "leaves multiple `range` clauses that are on different fields unmerged" do
        query = new_query(client_filter: {"age" => {"gt" => 10}, "height" => {"lte" => 120}})

        expect(datastore_body_of(query)).to filter_datastore_with(
          {range: {"age" => {gt: 10}}},
          {range: {"height" => {lte: 120}}}
        )
      end

      it "builds a `match` filter condition when given a `matches_query`: 'MatchesQueryFilterInput' filter" do
        query = new_query(
          client_filter: {
            "name_text" => {
              "matches_query" => {
                "query" => "foo",
                "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "DYNAMIC"),
                "require_all_terms" => false
              }
            }
          }
        )

        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match: {"name_text" => {query: "foo", fuzziness: "AUTO", operator: "OR"}}}]})
      end

      it "builds a `match` filter condition with specified fuzziness when given a `matches_query`: 'MatchesQueryFilterInput' filter" do
        query = new_query(
          client_filter: {
            "name_text" => {
              "matches_query" => {
                "query" => "foo",
                "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "NONE"),
                "require_all_terms" => false
              }
            }
          }
        )
        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match: {"name_text" => {query: "foo", fuzziness: "0", operator: "OR"}}}]})

        query = new_query(
          client_filter: {
            "name_text" => {
              "matches_query" => {
                "query" => "foo",
                "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "ONE"),
                "require_all_terms" => false
              }
            }
          }
        )
        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match: {"name_text" => {query: "foo", fuzziness: "1", operator: "OR"}}}]})

        query = new_query(
          client_filter: {
            "name_text" => {
              "matches_query" => {
                "query" => "foo",
                "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "TWO"),
                "require_all_terms" => false
              }
            }
          }
        )
        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match: {"name_text" => {query: "foo", fuzziness: "2", operator: "OR"}}}]})

        query = new_query(
          client_filter: {
            "name_text" => {
              "matches_query" => {
                "query" => "foo",
                "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "DYNAMIC"),
                "require_all_terms" => false
              }
            }
          }
        )
        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match: {"name_text" => {query: "foo", fuzziness: "AUTO", operator: "OR"}}}]})
      end

      it "builds a `match` filter condition with specified operator when given a `matches_query`: 'MatchesQueryFilterInput' filter" do
        query = new_query(
          client_filter: {
            "name_text" => {
              "matches_query" => {
                "query" => "foo",
                "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "DYNAMIC"),
                "require_all_terms" => true
              }
            }
          }
        )

        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match: {"name_text" => {query: "foo", fuzziness: "AUTO", operator: "AND"}}}]})
      end

      it "builds a `match_phrase_prefix` filter condition when given a `matches_phrase`: 'MatchesPhraseFilterInput' filter" do
        query = new_query(client_filter: {"name_text" => {"matches_phrase" => {"phrase" => "foo"}}})

        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match_phrase_prefix: {"name_text" => {query: "foo"}}}]})
      end

      it "builds a `match_bool_prefix` filter condition when given a `matches_query_with_prefix`: 'MatchesQueryWithPrefixFilterInput' filter" do
        query = new_query(
          client_filter: {
            "name_text" => {
              "matches_query_with_prefix" => {
                "query_with_prefix" => "foo",
                "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "DYNAMIC"),
                "require_all_terms" => false
              }
            }
          }
        )

        expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match_bool_prefix: {
          "name_text" => {
            query: "foo",
            fuzziness: "AUTO",
            operator: "OR"
          }
        }}]})
      end

      it "builds a `match_bool_prefix` filter condition with specified fuzziness when given a `matches_query_with_prefix` filter" do
        def test_fuzziness_for(allowed_edits_value, expected_fuzziness)
          query = new_query(
            client_filter: {
              "name_text" => {
                "matches_query_with_prefix" => {
                  "query_with_prefix" => "foo",
                  "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", allowed_edits_value),
                  "require_all_terms" => false
                }
              }
            }
          )
          expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match_bool_prefix: {
            "name_text" => {
              query: "foo",
              fuzziness: expected_fuzziness,
              operator: "OR"
            }
          }}]})
        end

        # Test each allowed_edits_per_term value with its expected fuzziness
        test_fuzziness_for("NONE", "0")
        test_fuzziness_for("ONE", "1")
        test_fuzziness_for("TWO", "2")
        test_fuzziness_for("DYNAMIC", "AUTO")
      end

      it "builds a `match_bool_prefix` filter condition with specified operator when given a `matches_query_with_prefix` filter" do
        def test_operator_for(require_all_terms, expected_operator)
          query = new_query(
            client_filter: {
              "name_text" => {
                "matches_query_with_prefix" => {
                  "query_with_prefix" => "foo",
                  "allowed_edits_per_term" => enum_value("MatchesQueryAllowedEditsPerTermInput", "DYNAMIC"),
                  "require_all_terms" => require_all_terms
                }
              }
            }
          )

          expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [{match_bool_prefix: {
            "name_text" => {
              query: "foo",
              fuzziness: "AUTO",
              operator: expected_operator
            }
          }}]})
        end

        # Test both values of require_all_terms with their expected operators
        test_operator_for(true, "AND")
        test_operator_for(false, "OR")
      end

      it "builds a `terms` condition on a nested path when given a deeply nested (3 levels) `equal_to_any_of: [...]` filter" do
        query = new_query(client_filter: {"options" => {"color" => {"red" => {"equal_to_any_of" => [100, 200]}}}})

        expect(datastore_body_of(query)).to filter_datastore_with(terms: {"options.color.red" => [100, 200]})
      end

      it "builds a `terms` condition on a nested path when given a nested (2 levels) `equal_to_any_of: [...]` filter" do
        query = new_query(client_filter: {"options" => {"size" => {"equal_to_any_of" => [10]}}})

        expect(datastore_body_of(query)).to filter_datastore_with(terms: {"options.size" => [10]})
      end

      it "supports an `equal_to_any_of` operator on multiple fields, converting them to multiple `terms` conditions" do
        query = new_query(client_filter: {"age" => {"equal_to_any_of" => [25, 30]}, "size" => {"equal_to_any_of" => [10]}})

        expect(datastore_body_of(query)).to filter_datastore_with(
          {terms: {"age" => [25, 30]}},
          {terms: {"size" => [10]}}
        )
      end

      describe "`contains`" do
        it "is ignored if it is empty in any form" do
          query = new_query(client_filter: {"name" => {"contains" => nil}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"contains" => {}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"contains" => {"ignore_case" => true}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => nil}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"contains" => {"all_substrings_of" => nil}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => nil, "all_substrings_of" => nil, "ignore_case" => true}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "translates each `all_substrings_of` value to a wildcard query, which are all ANDed together" do
          query = new_query(client_filter: {"name" => {"contains" => {"all_substrings_of" => ["foo", "bar", " "]}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}},
            {wildcard: {"name" => {value: "*bar*", case_insensitive: false}}},
            {wildcard: {"name" => {value: "* *", case_insensitive: false}}}
          )
        end

        it "translates each `any_substring_of` value to a wildcard query under a `should` clause to OR them together" do
          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo", "bar", " "]}}})

          expect(datastore_body_of(query)).to filter_datastore_with({bool: {
            minimum_should_match: 1,
            should: [
              {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}},
              {wildcard: {"name" => {value: "*bar*", case_insensitive: false}}},
              {wildcard: {"name" => {value: "* *", case_insensitive: false}}}
            ]
          }})
        end

        it "supports `all_substrings_of` and `any_substring_of` on the same filter" do
          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo", "bar"], "all_substrings_of" => ["bazz"]}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*bazz*", case_insensitive: false}}},
            {bool: {
              minimum_should_match: 1,
              should: [
                {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}},
                {wildcard: {"name" => {value: "*bar*", case_insensitive: false}}}
              ]
            }}
          )
        end

        it "returns a query that matches no documents when `any_substring_of` is empty" do
          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => []}}})

          expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => [], "all_substrings_of" => ["foo"]}}})

          expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)
        end

        it "ignores `all_substrings_of: []`" do
          query = new_query(client_filter: {"name" => {"contains" => {"all_substrings_of" => []}}})

          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo"], "all_substrings_of" => []}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}}
          )
        end

        it "avoids an unneeded `should` clause when `any_substring_of` has only one value, preserving the possibility of caching" do
          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo"]}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}}
          )

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo"], "all_substrings_of" => ["bar", "bazz"]}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*bar*", case_insensitive: false}}},
            {wildcard: {"name" => {value: "*bazz*", case_insensitive: false}}},
            {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}}
          )
        end

        it "uses a single wildcard of `*` when given an empty string" do
          query = new_query(client_filter: {"name" => {"contains" => {"all_substrings_of" => ["foo", ""]}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}},
            {wildcard: {"name" => {value: "*", case_insensitive: false}}}
          )

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => [""]}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*", case_insensitive: false}}}
          )
        end

        it "honors `ignore_case` and defaults it to false" do
          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo"], "all_substrings_of" => ["bar"]}}})
          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*bar*", case_insensitive: false}}},
            {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}}
          )

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo"], "all_substrings_of" => ["bar"], "ignore_case" => true}}})
          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*bar*", case_insensitive: true}}},
            {wildcard: {"name" => {value: "*foo*", case_insensitive: true}}}
          )

          query = new_query(client_filter: {"name" => {"contains" => {"any_substring_of" => ["foo"], "all_substrings_of" => ["bar"], "ignore_case" => false}}})
          expect(datastore_body_of(query)).to filter_datastore_with(
            {wildcard: {"name" => {value: "*bar*", case_insensitive: false}}},
            {wildcard: {"name" => {value: "*foo*", case_insensitive: false}}}
          )
        end
      end

      describe "`starts_with`" do
        it "is ignored if it is empty in any form" do
          query = new_query(client_filter: {"name" => {"starts_with" => nil}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"starts_with" => {}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"starts_with" => {"ignore_case" => true}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => nil}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all

          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => nil, "ignore_case" => true}}})
          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "translates each `any_prefix_of` value to a prefix query under a `should` clause to OR them together" do
          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => ["foo", "bar", " "]}}})

          expect(datastore_body_of(query)).to filter_datastore_with({bool: {
            minimum_should_match: 1,
            should: [
              {prefix: {"name" => {value: "foo", case_insensitive: false}}},
              {prefix: {"name" => {value: "bar", case_insensitive: false}}},
              {prefix: {"name" => {value: " ", case_insensitive: false}}}
            ]
          }})
        end

        it "returns a query that matches no documents when `any_prefix_of` is empty" do
          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => []}}})

          expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)
        end

        it "avoids an unneeded `should` clause when `any_prefix_of` has only one value, preserving the possibility of caching" do
          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => ["foo"]}}})

          expect(datastore_body_of(query)).to filter_datastore_with(
            {prefix: {"name" => {value: "foo", case_insensitive: false}}}
          )
        end

        it "honors `ignore_case` and defaults it to false" do
          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => ["foo", "bar"]}}})
          expect(datastore_body_of(query)).to filter_datastore_with({bool: {
            minimum_should_match: 1,
            should: [
              {prefix: {"name" => {value: "foo", case_insensitive: false}}},
              {prefix: {"name" => {value: "bar", case_insensitive: false}}}
            ]
          }})

          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => ["foo", "bar"], "ignore_case" => true}}})
          expect(datastore_body_of(query)).to filter_datastore_with({bool: {
            minimum_should_match: 1,
            should: [
              {prefix: {"name" => {value: "foo", case_insensitive: true}}},
              {prefix: {"name" => {value: "bar", case_insensitive: true}}}
            ]
          }})

          query = new_query(client_filter: {"name" => {"starts_with" => {"any_prefix_of" => ["foo", "bar"], "ignore_case" => false}}})
          expect(datastore_body_of(query)).to filter_datastore_with({bool: {
            minimum_should_match: 1,
            should: [
              {prefix: {"name" => {value: "foo", case_insensitive: false}}},
              {prefix: {"name" => {value: "bar", case_insensitive: false}}}
            ]
          }})
        end
      end

      describe "`equal_to_any_of` with `[nil]`" do
        it "builds a `must_not` `exists` condition when given an `equal_to_any_of: [nil]` filter" do
          query = new_query(client_filter: {"age" => {"equal_to_any_of" => [nil]}})

          expect(datastore_body_of(query)).to query_datastore_with({
            bool: {must_not: [
              {bool: {filter: [{exists: {"field" => "age"}}]}}
            ]}
          })
        end

        it "builds a `must_not` `exists` condition when given an `equal_to_any_of: [nil, nil]` filter" do
          query = new_query(client_filter: {"age" => {"equal_to_any_of" => [nil, nil]}})

          expect(datastore_body_of(query)).to query_datastore_with({
            bool: {must_not: [
              {bool: {filter: [{exists: {"field" => "age"}}]}}
            ]}
          })
        end

        it "handles `equal_to_any_of: [nil, non_nil_values, ...]` by ORing together multiple conditions (for a field that's not `id`)" do
          query = new_query(client_filter: {"age" => {"equal_to_any_of" => [nil, 25, 40]}})

          expect(datastore_body_of(query)).to filter_datastore_with({
            bool: {minimum_should_match: 1, should: [
              {bool: {filter: [{terms: {"age" => [25, 40]}}]}},
              {bool: {must_not: [{bool: {filter: [{exists: {"field" => "age"}}]}}]}}
            ]}
          })
        end

        it "handles `equal_to_any_of: [nil, non_nil_values, ...]` by ORing together multiple conditions (for the `id` field)" do
          query = new_query(client_filter: {"id" => {"equal_to_any_of" => [nil, 25, 40]}})

          expect(datastore_body_of(query)).to filter_datastore_with({
            bool: {minimum_should_match: 1, should: [
              {bool: {filter: [{ids: {values: [25, 40]}}]}},
              {bool: {must_not: [{bool: {filter: [{exists: {"field" => "id"}}]}}]}}
            ]}
          })
        end

        it "builds an `exists` condition when given a `not` equal_to_any_of filter" do
          query = new_query(client_filter: {"not" => {"age" => {"equal_to_any_of" => [nil]}}})

          expect(datastore_body_of(query)).to query_datastore_with({
            bool: {filter: [{exists: {"field" => "age"}}]}
          })
        end

        it "builds an `exists` condition when given `equal_to_any_of: [nil]` filter, and does not drop other boolean occurrences" do
          query = new_query(client_filter: {
            "age" => {"equal_to_any_of" => [nil]},
            "color" => {"equal_to_any_of" => %w[blue green]}
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {
            filter: [{terms: {"color" => %w[blue green]}}],
            must_not: [{bool: {filter: [{exists: {"field" => "age"}}]}}]
          }})
        end

        it "builds an `exists` condition when given `equal_to_any_of: [nil]` filter, and combines must_not occurrences" do
          query = new_query(client_filter: {
            "age" => {"equal_to_any_of" => [nil]},
            "color" => {"not" => {"equal_to_any_of" => %w[blue green]}}
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {
            must_not: [
              {bool: {filter: [{exists: {"field" => "age"}}]}},
              {bool: {filter: [{terms: {"color" => %w[blue green]}}]}}
            ]
          }})
        end

        it "builds an `exists` condition when given a `not` `equal_to_any_of` filter, and combines it with other boolean occurrences" do
          query = new_query(client_filter: {
            "not" => {"age" => {"equal_to_any_of" => [nil]}},
            "color" => {"equal_to_any_of" => %w[blue green]}
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {
            filter: [
              {exists: {"field" => "age"}},
              {terms: {"color" => %w[blue green]}}
            ]
          }})
        end

        it "builds an `exists` condition when given a `not` `equal_to_any_of` filter, and does not drop other negated boolean occurrences" do
          query = new_query(client_filter: {
            "age" => {"not" => {"equal_to_any_of" => [nil]}},
            "color" => {"not" => {"equal_to_any_of" => %w[blue green]}}
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {
            filter: [{exists: {"field" => "age"}}],
            must_not: [{bool: {filter: [{terms: {"color" => %w[blue green]}}]}}]
          }})
        end

        it "builds an `exists` when `equal_to_any_of: [nil]` is the only filter and nested in `any_of`" do
          query = new_query(client_filter: {"any_of" => [
            {"age" => {"equal_to_any_of" => [nil]}}
          ]})

          expect(datastore_body_of(query)).to query_datastore_with({
            bool: {
              minimum_should_match: 1,
              should: [{bool: {must_not: [{bool: {filter: [{exists: {"field" => "age"}}]}}]}}]
            }
          })
        end

        it "builds an `exists` when the `equal_to_any_of: [nil]` part is among other filters" do
          query = new_query(client_filter: {
            "name" => {"equal_to_any_of" => ["foo"]},
            "age" => {"equal_to_any_of" => [nil]},
            "currency" => {"equal_to_any_of" => ["USD"]}
          })

          expect(datastore_body_of(query)).to query_datastore_with({
            bool: {
              filter: [
                {terms: {"name" => ["foo"]}},
                {terms: {"currency" => ["USD"]}}
              ],
              must_not: [{bool: {filter: [{exists: {"field" => "age"}}]}}]
            }
          })
        end
      end

      describe "`all_of` operator" do
        it "produces a separate bool subfilter for each clause" do
          query = new_query(client_filter: {"all_of" => [
            {"color" => {"equal_to_any_of" => ["RED"]}},
            {"size" => {"gt" => 10}}
          ]})

          expect(datastore_body_of(query)).to query_datastore_with(bool: {
            filter: [
              {
                bool: {
                  filter: [
                    {terms: {"color" => ["RED"]}}
                  ]
                }
              },
              {
                bool: {
                  filter: [
                    {range: {"size" => {gt: 10}}}
                  ]
                }
              }
            ]
          })
        end

        it "allows ANDing two subfilters on the same field" do
          query = new_query(client_filter: {
            "all_of" => [
              {"color" => {"equal_to_any_of" => ["RED"]}},
              {"color" => {"not" => {"equal_to_any_of" => ["GREEN"]}}}
            ]
          })

          expect(datastore_body_of(query)).to query_datastore_with(
            bool: {
              filter: [
                {
                  bool: {
                    filter: [
                      {terms: {"color" => ["RED"]}}
                    ]
                  }
                },
                {
                  bool: {
                    must_not: [
                      {
                        bool: {
                          filter: [
                            {terms: {"color" => ["GREEN"]}}
                          ]
                        }
                      }
                    ]
                  }
                }
              ]
            }
          )
        end

        it "allows an AND of multiple OR subfilters (i.e. allOf of anyOfs)" do
          query = new_query(client_filter: {
            "all_of" => [
              {
                "any_of" => [
                  {"color" => {"equal_to_any_of" => ["RED"]}},
                  {"size" => {"gt" => 10}}
                ]
              },
              {
                "any_of" => [
                  {"color" => {"equal_to_any_of" => ["BLUE"]}},
                  {"size" => {"lt" => 5}}
                ]
              }
            ]
          })

          expect(datastore_body_of(query)).to query_datastore_with(bool: {
            filter: [
              {
                bool: {
                  minimum_should_match: 1,
                  should: [
                    {bool: {filter: [{terms: {"color" => ["RED"]}}]}},
                    {bool: {filter: [{range: {"size" => {gt: 10}}}]}}
                  ]
                }
              },
              {
                bool: {
                  minimum_should_match: 1,
                  should: [
                    {bool: {filter: [{terms: {"color" => ["BLUE"]}}]}},
                    {bool: {filter: [{range: {"size" => {lt: 5}}}]}}
                  ]
                }
              }
            ]
          })
        end

        it "can be used to wrap multiple `any_satisfy` expressions to require multiple sub-filters to be satisfied by a list element" do
          query = new_query(client_filter: {
            "tags" => {"all_of" => [
              {"any_satisfy" => {"equal_to_any_of" => ["a", "b"]}},
              {"any_satisfy" => {"equal_to_any_of" => ["c", "d"]}}
            ]}
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {
            filter: [
              {bool: {filter: [{terms: {"tags" => ["a", "b"]}}]}},
              {bool: {filter: [{terms: {"tags" => ["c", "d"]}}]}}
            ]
          }})
        end

        it "handles `not` within `all_of` operator" do
          query = new_query(client_filter: {
            "all_of" => [
              {"amount_cents" => {"gt" => 50}},
              {"not" => {"tags" => {"any_satisfy" => {"equal_to_any_of" => ["foo"]}}}}
            ]
          })

          expect(datastore_body_of(query)).to query_datastore_with(bool: {
            filter: [
              {
                bool: {
                  filter: [
                    {range: {"amount_cents" => {gt: 50}}}
                  ]
                }
              },
              {
                bool: {
                  must_not: [
                    {bool: {filter: [{terms: {"tags" => ["foo"]}}]}}
                  ]
                }
              }
            ]
          })
        end

        it "handles empty predicates" do
          query = new_query(client_filter: {
            "all_of" => [
              {},
              {"amount_cents" => {"gt" => 50}}
            ]
          })

          expect(datastore_body_of(query)).to query_datastore_with(bool: {
            filter: [
              {bool: {filter: [{range: {"amount_cents" => {gt: 50}}}]}}
            ]
          })

          query = new_query(client_filter: {
            "all_of" => [
              {"amount_cents" => {}},
              {"amount_cents" => {"gt" => 50}}
            ]
          })

          expect(datastore_body_of(query)).to query_datastore_with(bool: {
            filter: [
              {bool: {filter: [{range: {"amount_cents" => {gt: 50}}}]}}
            ]
          })
        end

        it "handles not with empty predicate" do
          query = new_query(client_filter: {
            "all_of" => [
              {"not" => {}},
              {"amount_cents" => {"gt" => 50}}
            ]
          })

          expect(datastore_body_of(query)).to query_datastore_with(bool: {
            filter: [
              {
                bool: {
                  filter: [
                    {match_none: {}}
                  ]
                }
              },
              {
                bool: {
                  filter: [
                    {range: {"amount_cents" => {gt: 50}}}
                  ]
                }
              }
            ]
          })
        end

        it "is treated as `true` when `null` is passed" do
          query = new_query(client_filter: {"tags" => {"all_of" => nil}})

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "is treated as `true` when `[]` is passed" do
          query = new_query(client_filter: {"tags" => {"all_of" => []}})

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end
      end

      describe "`any_satisfy` operator" do
        context "on a list-of-scalars field" do
          it "returns the body of the sub-filters because the semantics indicated by `any_satisfy` is what the datastore automatically provides on list fields" do
            query1 = new_query(client_filter: {
              "tags" => {"any_satisfy" => {"equal_to_any_of" => ["a", "b"]}},
              "ages" => {"any_satisfy" => {"gt" => 30}}
            })

            query2 = new_query(client_filter: {
              "tags" => {"equal_to_any_of" => ["a", "b"]},
              "ages" => {"gt" => 30}
            })

            expect(datastore_body_of(query1)).to eq(datastore_body_of(query2))
          end

          it "merges multiple range operators into a single clause to force a single value to satisfy all (rather than separate values satisfying each)" do
            query = new_query(client_filter: {
              "ages" => {"any_satisfy" => {"gt" => 30, "lt" => 60}}
            })

            expect(datastore_body_of(query)).to query_datastore_with({bool: {filter: [{range: {"ages" => {
              gt: 30,
              lt: 60
            }}}]}})
          end

          context "when using `snake_case` schema names" do
            let(:graphql) { build_graphql(schema_element_name_form: :snake_case) }

            it "rejects a query that produces multiple query clauses under `any_satisfy` because the datastore does not require a single value to match them all" do
              query = new_query(client_filter: {
                # We don't expect users to send us a filter like this, but if they did, we can't support it.
                "ages" => {"any_satisfy" => {"gt" => 30, "equal_to_any_of" => [50]}}
              })

              expect {
                datastore_body_of(query)
              }.to raise_error ::GraphQL::ExecutionError, a_string_including(
                "`any_satisfy: {gt: 30, equal_to_any_of: [50]}` is not supported because it produces multiple filtering clauses under `any_satisfy`"
              )
            end
          end

          context "when using `camelCase` schema names" do
            let(:graphql) { build_graphql(schema_element_name_form: :camelCase) }

            it "rejects a query that produces multiple query clauses under `any_satisfy` because the datastore does not require a single value to match them all" do
              query = new_query(client_filter: {
                # We don't expect users to send us a filter like this, but if they did, we can't support it.
                "ages" => {"anySatisfy" => {"gt" => 30, "equalToAnyOf" => [50]}}
              })

              expect {
                datastore_body_of(query)
              }.to raise_error ::GraphQL::ExecutionError, a_string_including(
                "`anySatisfy: {gt: 30, equalToAnyOf: [50]}` is not supported because it produces multiple filtering clauses under `anySatisfy`"
              )
            end
          end

          it "still allows multiple query clauses under `any_satisfy: {any_of: [...]}}` because that has OR semantics" do
            query = new_query(client_filter: {
              "ages" => {"any_satisfy" => {"any_of" => [{"gt" => 30}, {"equal_to_any_of" => [50]}]}}
            })

            expect(datastore_body_of(query)).to query_datastore_with({bool: {minimum_should_match: 1, should: [
              {bool: {filter: [{range: {"ages" => {gt: 30}}}]}},
              {bool: {filter: [{terms: {"ages" => [50]}}]}}
            ]}})
          end

          it "does not allow `any_of` alongside another filter because that would also produce multiple query clauses that we can't support" do
            query = new_query(client_filter: {
              "ages" => {"any_satisfy" => {"any_of" => [{"gt" => 30}], "equal_to_any_of" => [50]}}
            })

            expect {
              datastore_body_of(query)
            }.to raise_error ::GraphQL::ExecutionError, a_string_including(
              "`any_satisfy: {any_of: [{gt: 30}], equal_to_any_of: [50]}` is not supported because it produces multiple filtering clauses under `any_satisfy`"
            )
          end

          it "returns the standard always false filter for `any_satisfy: {any_of: []}`" do
            query = new_query(client_filter: {
              "ages" => {"any_satisfy" => {"any_of" => []}}
            })

            expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)
          end

          it "applies no filtering when given `any_satisfy: {}`" do
            query = new_query(client_filter: {
              "ages" => {"any_satisfy" => {}}
            })

            expect(datastore_body_of(query)).to not_filter_datastore_at_all
          end
        end

        context "on a list-of-nested-objects field" do
          it "builds a `nested` filter" do
            query = new_query(client_filter: {
              "people" => {"friends" => {"any_satisfy" => {"age" => {"gt" => 30}}}}
            })

            expect(datastore_body_of(query)).to filter_datastore_with({nested: {
              path: "people.friends",
              query: {bool: {filter: [{
                range: {"people.friends.age" => {gt: 30}}
              }]}}
            }})
          end

          it "correctly builds a `nested` filter when `any_satisfy: {not: ...}` is used" do
            query = new_query(client_filter: {
              "people" => {"friends" => {"any_satisfy" => {"not" => {"age" => {"gt" => 30}}}}}
            })

            expect(datastore_body_of(query)).to filter_datastore_with({nested: {
              path: "people.friends",
              query: {bool: {must_not: [{bool: {filter: [{
                range: {"people.friends.age" => {gt: 30}}
              }]}}]}}
            }})
          end

          it "correctly builds a `nested` filter when `any_satisfy: {field: {any_satisfy: ...}}}` is used" do
            query = new_query(client_filter: {
              "line_items" => {"any_satisfy" => {"tags" => {"any_satisfy" => {"equal_to_any_of" => ["a"]}}}}
            })

            expect(datastore_body_of(query)).to filter_datastore_with({nested: {
              path: "line_items",
              query: {bool: {filter: [{
                terms: {"line_items.tags" => ["a"]}
              }]}}
            }})
          end

          it "correctly builds a `nested` filter when `any_satisfy: {any_of: [{field: ...}]}` is used" do
            query = new_query(client_filter: {
              "line_items" => {"any_satisfy" => {"any_of" => [{"name" => {"equal_to_any_of" => ["a"]}}]}}
            })

            expect(datastore_body_of(query)).to filter_datastore_with({nested: {
              path: "line_items",
              query: {bool: {
                minimum_should_match: 1,
                should: [{bool: {filter: [{
                  terms: {"line_items.name" => ["a"]}
                }]}}]
              }}
            }})
          end

          it "builds an empty filter when given `any_satisfy: {field: {}}`" do
            query = new_query(client_filter: {
              "line_items" => {"any_satisfy" => {"name" => {}}}
            })

            expect(datastore_body_of(query)).to not_filter_datastore_at_all
          end

          it "builds an empty filter when given `any_satisfy: {field: {predicate: nil}}`" do
            query = new_query(client_filter: {
              "line_items" => {"any_satisfy" => {"name" => {"equal_to_any_of" => nil}}}
            })

            expect(datastore_body_of(query)).to not_filter_datastore_at_all
          end
        end
      end

      # Note: a `count` filter gets translated into `__counts` (to distinguish it from a schema field named `count`),
      # and that translation happens as the query is being built, so we use `__counts` in our example filters here.
      describe "`count` operator on a list" do
        it "builds a query on the hidden `#{LIST_COUNTS_FIELD}` field where we have indexed list counts" do
          query = new_query(client_filter: {
            "past_names" => {LIST_COUNTS_FIELD => {"gt" => 10}}
          })

          expect(datastore_body_of(query)).to filter_datastore_with(range: {
            "#{LIST_COUNTS_FIELD}.past_names" => {gt: 10}
          })
        end

        it "correctly references a list field embedded on an object field" do
          query = new_query(client_filter: {
            "details" => {"uniform_colors" => {LIST_COUNTS_FIELD => {"gt" => 10}}}
          })

          expect(datastore_body_of(query)).to filter_datastore_with(range: {
            "#{LIST_COUNTS_FIELD}.details|uniform_colors" => {gt: 10}
          })
        end

        it "correctly references a list field under a list-of-nested-objects field" do
          query = new_query(client_filter: {
            "seasons_nested" => {"any_satisfy" => {"notes" => {LIST_COUNTS_FIELD => {"gt" => 10}}}}
          })

          expect(datastore_body_of(query)).to filter_datastore_with({nested: {
            path: "seasons_nested",
            query: {bool: {filter: [{
              range: {"seasons_nested.#{LIST_COUNTS_FIELD}.notes" => {gt: 10}}
            }]}}
          }})
        end

        it "treats a filter on a `count` schema field like a filter on any other schema field" do
          query = new_query(client_filter: {
            "past_names" => {"count" => {"gt" => 10}}
          })

          expect(datastore_body_of(query)).to filter_datastore_with(range: {
            "past_names.count" => {gt: 10}
          })
        end

        describe "including an extra must_not exists filter for a predicate that matches zero in order to match documents indexed before the list field got defined" do
          it "correctly detects when an `lt` expression could match zero" do
            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lt" => 10}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lt: 10}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lt" => 1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lt: 1}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lt" => 0}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lt: 0}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lt" => -1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lt: -1}
            })
          end

          it "correctly detects when an `lte` expression could match zero" do
            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lte" => 10}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lte: 10}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lte" => 1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lte: 1}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lte" => 0}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lte: 0}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"lte" => -1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lte: -1}
            })
          end

          it "correctly detects when an `gt` expression could match zero" do
            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gt" => -10}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gt: -10}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gt" => -1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gt: -1}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gt" => 0}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gt: 0}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gt" => 1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gt: 1}
            })
          end

          it "correctly detects when an `gte` expression could match zero" do
            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gte" => -10}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gte: -10}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gte" => -1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gte: -1}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gte" => 0}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gte: 0}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gte" => 1}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gte: 1}
            })
          end

          it "correctly detects when an `equal_to_any_of` could match zero" do
            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"equal_to_any_of" => [3, 0, 5]}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(terms: {
              "#{LIST_COUNTS_FIELD}.past_names" => [3, 0, 5]
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"equal_to_any_of" => [3, 5]}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(terms: {
              "#{LIST_COUNTS_FIELD}.past_names" => [3, 5]
            })
          end

          it "correct detects when an expression with multiple predicates could match zero" do
            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gte" => 0, "lt" => 10}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gte: 0, lt: 10}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gte" => 1, "lt" => 10}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gte: 1, lt: 10}
            })

            query = new_query(client_filter: {
              "past_names" => {LIST_COUNTS_FIELD => {"gte" => 0, "lt" => 0}}
            })
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gte: 0, lt: 0}
            })
          end

          it "treats `count` filter predicates that have a `nil` or `{}` value as `true`" do
            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => nil}})
            expect(datastore_body_of(query)).to not_filter_datastore_at_all

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {}}})
            expect(datastore_body_of(query)).to not_filter_datastore_at_all

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {"gt" => nil}}})
            expect(datastore_body_of(query)).to not_filter_datastore_at_all

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {"gte" => nil}}})
            expect(datastore_body_of(query)).to not_filter_datastore_at_all

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {"lt" => nil}}})
            expect(datastore_body_of(query)).to not_filter_datastore_at_all

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {"lte" => nil}}})
            expect(datastore_body_of(query)).to not_filter_datastore_at_all

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {"equal_to_any_of" => nil}}})
            expect(datastore_body_of(query)).to not_filter_datastore_at_all

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {"gt" => nil, "lt" => 10}}})
            expect(datastore_body_of(query)).to filter_datastore_with_must_not_exists_or(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {lt: 10}
            })

            query = new_query(client_filter: {"past_names" => {LIST_COUNTS_FIELD => {"gt" => 10, "lt" => nil}}})
            expect(datastore_body_of(query)).to filter_datastore_with(range: {
              "#{LIST_COUNTS_FIELD}.past_names" => {gt: 10}
            })
          end

          def filter_datastore_with_must_not_exists_or(other)
            filter_datastore_with(bool: {
              should: [
                {bool: {filter: [other]}},
                {bool: {must_not: [{bool: {filter: [
                  {exists: {"field" => "#{LIST_COUNTS_FIELD}.past_names"}}
                ]}}]}}
              ],
              minimum_should_match: 1
            })
          end
        end
      end

      describe "`near` operator" do
        datastore_abbreviations_by_distance_unit = {
          "MILE" => "mi",
          "FOOT" => "ft",
          "INCH" => "in",
          "YARD" => "yd",
          "KILOMETER" => "km",
          "METER" => "m",
          "CENTIMETER" => "cm",
          "MILLIMETER" => "mm",
          "NAUTICAL_MILE" => "nmi"
        }

        shared_examples_for "`near` filtering with all distance units" do |enum_type_name|
          let(:distance_unit_enum) { graphql.schema.type_named(enum_type_name) }

          specify "the examples here cover all `#{enum_type_name}` values" do
            expect(
              graphql.runtime_metadata.enum_types_by_name.fetch(enum_type_name).values_by_name.keys
            ).to match_array(datastore_abbreviations_by_distance_unit.keys)
          end

          datastore_abbreviations_by_distance_unit.each do |distance_unit, datastore_abbreviation|
            it "supports filtering using the `#{distance_unit}` distance unit" do
              query = new_query(client_filter: {"address_location" => {"near" => {
                "latitude" => 37.5,
                "longitude" => 67.5,
                "max_distance" => 500,
                "unit" => distance_unit_enum.enum_value_named(distance_unit)
              }}})

              expect(datastore_body_of(query)).to filter_datastore_with(
                geo_distance: {
                  "distance" => "500#{datastore_abbreviation}",
                  "address_location" => {
                    "lat" => 37.5,
                    "lon" => 67.5
                  }
                }
              )
            end
          end
        end

        context "when using the standard `InputEnum` naming format" do
          include_examples "`near` filtering with all distance units", "DistanceUnitInput"
        end

        context "when configured to use an alternate `InputEnum` naming format" do
          attr_accessor :schema_artifacts

          before(:context) do
            self.schema_artifacts = generate_schema_artifacts(derived_type_name_formats: {InputEnum: "%{base}InputAlt"})
          end

          let(:graphql) { build_graphql(schema_artifacts: schema_artifacts) }
          include_examples "`near` filtering with all distance units", "DistanceUnitInputAlt"
        end
      end

      context "when there are no `GeoLocation` fields" do
        let(:graphql) do
          schema_artifacts = build_datastore_core.schema_artifacts
          runtime_meta = schema_artifacts.runtime_metadata.with(
            enum_types_by_name: schema_artifacts.runtime_metadata.enum_types_by_name.except("DistanceUnit")
          )

          allow(schema_artifacts).to receive(:runtime_metadata).and_return(runtime_meta)
          build_graphql(schema_artifacts: schema_artifacts)
        end

        specify "the `near` filter implementation doesn't fail due to a lack of a `DistanceUnit` type" do
          expect(graphql.runtime_metadata.enum_types_by_name.keys).to exclude("DistanceUnit")

          query = new_query(client_filter: {"id" => {"equal_to_any_of" => ["a"]}})

          expect(datastore_body_of(query)).to filter_datastore_with({ids: {values: ["a"]}})
        end
      end

      describe "`time_of_day` operator" do
        it "uses a `script` query, passing along the `gte` param" do
          query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_of_day" => {"gte" => "07:00:00"}}}})

          expect_script_query_with_params(query, {
            field: "timestamps.created_at",
            gte: "07:00:00"
          })
        end

        it "uses a `script` query, passing along the `gt` param" do
          query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_of_day" => {"gt" => "07:00:00"}}}})

          expect_script_query_with_params(query, {
            field: "timestamps.created_at",
            gt: "07:00:00"
          })
        end

        it "uses a `script` query, passing along the `lte` param" do
          query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_of_day" => {"lte" => "07:00:00"}}}})

          expect_script_query_with_params(query, {
            field: "timestamps.created_at",
            lte: "07:00:00"
          })
        end

        it "uses a `script` query, passing along the `lt` param" do
          query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_of_day" => {"lt" => "07:00:00"}}}})

          expect_script_query_with_params(query, {
            field: "timestamps.created_at",
            lt: "07:00:00"
          })
        end

        it "uses a `script` query, passing along the `equal_to_any_of` param" do
          query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_of_day" => {"equal_to_any_of" => ["07:00:00", "08:00:00"]}}}})

          expect_script_query_with_params(query, {
            field: "timestamps.created_at",
            equal_to_any_of: ["07:00:00", "08:00:00"]
          })
        end

        it "uses a `script` query, passing along the `time_zone` param" do
          query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_of_day" => {
            "time_zone" => "America/Los_Angeles",
            # We have to include at least one comparison operator so that the filter is included in the datastore body.
            "gt" => "08:00:00"
          }}}})

          expect_script_query_with_params(query, {
            field: "timestamps.created_at",
            time_zone: "America/Los_Angeles",
            gt: "08:00:00"
          })
        end

        it "omits the filter from the query payload when no operators are provided" do
          query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_of_day" => {"time_zone" => "America/Los_Angeles"}}}})

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        context "when configured to use different schema element names" do
          let(:graphql) do
            build_graphql(schema_element_name_overrides: {
              gt: "greater",
              lt: "lesser",
              gte: "greater_or_equal",
              lte: "lesser_or_equal",
              equal_to_any_of: "in",
              time_zone: "tz",
              time_of_day: "time_part"
            })
          end

          it "recognizes the alternate schema element names but uses our standard names in the script params because the script expects that" do
            query = new_query(client_filter: {"timestamps" => {"created_at" => {"time_part" => {
              "tz" => "America/Los_Angeles",
              "greater" => "01:00:00",
              "lesser" => "02:00:00",
              "greater_or_equal" => "03:00:00",
              "lesser_or_equal" => "04:00:00",
              "in" => ["05:00:00"]
            }}}})

            expect_script_query_with_params(query, {
              field: "timestamps.created_at",
              time_zone: "America/Los_Angeles",
              gt: "01:00:00",
              lt: "02:00:00",
              gte: "03:00:00",
              lte: "04:00:00",
              equal_to_any_of: ["05:00:00"]
            })
          end
        end

        def expect_script_query_with_params(query, expected_params)
          body = datastore_body_of(query)
          script_args = body.dig(:query, :bool, :filter, 0, :script, :script)

          expect(script_args.keys).to include(:id, :params)
          expect(script_args[:id]).to start_with("filter_by_time_of_day_")

          expected_params_in_nanos = expected_params.transform_values do |value|
            case value
            when /^\d\d:/
              Support::TimeUtil.nano_of_day_from_local_time(value)
            when ::Array
              value.map { |v| Support::TimeUtil.nano_of_day_from_local_time(v) }
            else
              value
            end
          end

          expect(script_args[:params]).to eq(expected_params_in_nanos)
        end
      end

      it "supports an `any_of` operator" do
        query = new_query(client_filter: {
          "any_of" => [
            {
              "transaction_type" => {"equal_to_any_of" => ["CARD"]},
              "total_amount" => {
                "any_of" => [
                  {"amount" => {"gt" => 10000}},
                  {
                    "amount" => {"gt" => 1000},
                    "currency" => {"equal_to_any_of" => ["USD"]}
                  }
                ]
              }
            },
            {
              "transaction_type" => {"equal_to_any_of" => ["CASH"]}
            }
          ]
        })

        expect(datastore_body_of(query)).to query_datastore_with({
          bool: {minimum_should_match: 1, should: [
            {
              bool: {
                filter: [
                  {terms: {"transaction_type" => ["CARD"]}},
                  {bool: {minimum_should_match: 1, should: [
                    {bool: {filter: [
                      {range: {"total_amount.amount" => {gt: 10000}}}
                    ]}},
                    {bool: {filter: [
                      {range: {"total_amount.amount" => {gt: 1000}}},
                      {terms: {"total_amount.currency" => ["USD"]}}
                    ]}}
                  ]}}
                ]
              }
            },
            {
              bool: {filter: [
                {terms: {"transaction_type" => ["CASH"]}}
              ]}
            }
          ]}
        })
      end

      it "handles `any_of` used at nested cousin nodes correctly" do
        query = new_query(client_filter: {
          "cost" => {
            "any_of" => [
              {"currency" => {"equal_to_any_of" => ["USD"]}},
              {"amount_cents" => {"gt" => 100}}
            ]
          },
          "options" => {
            "any_of" => [
              {"size" => {"equal_to_any_of" => [size_of("MEDIUM")]}},
              {"color" => {"equal_to_any_of" => [color_of("RED")]}}
            ]
          }
        })

        expect(datastore_body_of(query)).to query_datastore_with({bool: {filter: [
          {
            bool: {
              minimum_should_match: 1, should: [
                {bool: {filter: [
                  {terms: {"cost.currency" => ["USD"]}}
                ]}},
                {bool: {filter: [
                  {range: {"cost.amount_cents" => {gt: 100}}}
                ]}}
              ]
            }
          },
          {
            bool: {
              minimum_should_match: 1, should: [
                {bool: {filter: [
                  {terms: {"options.size" => ["MEDIUM"]}}
                ]}},
                {bool: {filter: [
                  {terms: {"options.color" => ["RED"]}}
                ]}}
              ]
            }
          }
        ]}})
      end

      describe "`not`" do
        it "negates the inner filter expression, regardless of where the `not` goes" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {"not" => {
            "equal_to_any_of" => [25, 30]
          }}}))

          body_for_outer_not = datastore_body_of(new_query(client_filter: {"not" => {"age" => {
            "equal_to_any_of" => [25, 30]
          }}}))

          expect(body_for_inner_not).to eq(body_for_outer_not).and query_datastore_with({bool: {must_not: [{bool: {filter: [{terms: {"age" => [25, 30]}}]}}]}})
        end

        it "can negate multiple inner filter predicates" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {"not" => {
            "gte" => 30,
            "lt" => 25
          }}}))

          body_for_outer_not = datastore_body_of(new_query(client_filter: {"not" => {"age" => {
            "gte" => 30,
            "lt" => 25
          }}}))

          expect(body_for_inner_not).to eq(body_for_outer_not).and query_datastore_with({bool: {must_not: [{bool: {filter: [
            {range: {"age" => {gte: 30, lt: 25}}}
          ]}}]}})
        end

        it "negates a complex compound inner filter expression" do
          query = new_query(client_filter: {"not" => {
            "any_of" => [
              {
                "transaction_type" => {"equal_to_any_of" => ["CARD"]},
                "total_amount" => {
                  "any_of" => [
                    {"amount" => {"gt" => 10000}},
                    {
                      "amount" => {"gt" => 1000},
                      "currency" => {"equal_to_any_of" => ["USD"]}
                    }
                  ]
                }
              },
              {
                "transaction_type" => {"equal_to_any_of" => ["CASH"]}
              }
            ]
          }})

          expect(datastore_body_of(query)).to query_datastore_with({
            bool: {must_not: [{bool: {minimum_should_match: 1, should: [
              {
                bool: {
                  filter: [
                    {terms: {"transaction_type" => ["CARD"]}},
                    {bool: {minimum_should_match: 1, should: [
                      {bool: {filter: [
                        {range: {"total_amount.amount" => {gt: 10000}}}
                      ]}},
                      {bool: {filter: [
                        {range: {"total_amount.amount" => {gt: 1000}}},
                        {terms: {"total_amount.currency" => ["USD"]}}
                      ]}}
                    ]}}
                  ]
                }
              },
              {
                bool: {filter: [
                  {terms: {"transaction_type" => ["CASH"]}}
                ]}
              }
            ]}}]}
          })
        end

        it "works correctly when included alongside other filtering operators" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {
            "not" => {"equal_to_any_of" => [15, 30]},
            "gte" => 20
          }}))

          body_for_outer_not = datastore_body_of(new_query(client_filter: {
            "not" => {
              "age" => {"equal_to_any_of" => [15, 30]}
            },
            "age" => {
              "gte" => 20
            }
          }))

          expect(body_for_inner_not).to eq(body_for_outer_not).and query_datastore_with({bool: {
            filter: [{range: {"age" => {gte: 20}}}],
            must_not: [{bool: {filter: [{terms: {"age" => [15, 30]}}]}}]
          }})
        end

        it "works correctly when included alongside an `any_of`" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {
            "not" => {"equal_to_any_of" => [15, 50]},
            "any_of" => [
              {"gt" => 35},
              {"lt" => 20}
            ]
          }}))

          body_for_outer_not = datastore_body_of(new_query(client_filter: {
            "not" => {
              "age" => {"equal_to_any_of" => [15, 50]}
            },
            "age" => {
              "any_of" => [
                {"gt" => 35},
                {"lt" => 20}
              ]
            }
          }))

          # The location of the `client_filter: [{bool: }]` wrapper differs between `body_for_inner_not` and `body_for_outer_not` but does not impact behavior.
          # These two queries yield the same results - confirmed by the integration test "`not` works correctly when included alongside an `any_of`",
          # so even though the behavior is the same, we must assert on the two payloads separately.
          expect(body_for_inner_not).to query_datastore_with({bool: {filter: [{bool: {
            must_not: [
              {bool: {filter: [{terms: {"age" => [15, 50]}}]}}
            ],
            should: [
              {bool: {filter: [{range: {"age" => {gt: 35}}}]}},
              {bool: {filter: [{range: {"age" => {lt: 20}}}]}}
            ],
            minimum_should_match: 1
          }}]}})

          expect(body_for_outer_not).to query_datastore_with({bool: {
            must_not: [
              {bool: {filter: [{terms: {"age" => [15, 50]}}]}}
            ],
            filter: [
              {bool: {
                should: [
                  {bool: {filter: [{range: {"age" => {gt: 35}}}]}},
                  {bool: {filter: [{range: {"age" => {lt: 20}}}]}}
                ],
                minimum_should_match: 1
              }}
            ]
          }})
        end

        it "returns the standard always false filter when set to nil" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {"not" => nil}}))
          body_for_outer_not = datastore_body_of(new_query(client_filter: {"not" => {"age" => nil}}))

          expect(body_for_inner_not).to eq(body_for_outer_not).and query_datastore_with(always_false_condition)
        end

        it "returns the standard always false filter when set to an emptyPredicate" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {"not" => {}}}))
          body_for_outer_not = datastore_body_of(new_query(client_filter: {"not" => {"age" => {}}}))

          expect(body_for_inner_not).to eq(body_for_outer_not).and query_datastore_with(always_false_condition)
        end

        it "returns the standard always false filter when set to nil alongside other filters" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {
            "not" => nil,
            "gt" => 25
          }}))

          body_for_outer_not = datastore_body_of(new_query(client_filter: {
            "not" => nil,
            "age" => {
              "gt" => 25
            }
          }))

          expect(body_for_inner_not).to eq(body_for_outer_not).and query_datastore_with({bool: {filter: [{match_none: {}}, {range: {"age" => {gt: 25}}}]}})
        end

        it "returns the standard always false filter when set to nil alongside other filters inside `any_of`" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {
            "any_of" => [
              {"not" => nil},
              {"gt" => 25}
            ]
          }}))

          body_for_outer_not = datastore_body_of(new_query(client_filter: {
            "any_of" => [
              {"not" => nil},
              {
                "age" => {
                  "gt" => 25
                }
              }
            ]
          }))

          expect(body_for_inner_not).to query_datastore_with({bool: {filter: [{bool: {minimum_should_match: 1, should: [
            {bool: {filter: [{match_none: {}}]}}, {bool: {filter: [{range: {"age" => {gt: 25}}}]}}
          ]}}]}})
          expect(body_for_outer_not).to query_datastore_with({bool: {minimum_should_match: 1, should: [
            {bool: {filter: [{match_none: {}}]}}, {bool: {filter: [{range: {"age" => {gt: 25}}}]}}
          ]}})
        end

        it "returns the standard always false filter when the inner filter evaluates to true" do
          body_for_inner_not = datastore_body_of(new_query(client_filter: {"age" => {"not" => {"equal_to_any_of" => nil}}}))
          body_for_outer_not = datastore_body_of(new_query(client_filter: {"not" => {"age" => {"equal_to_any_of" => nil}}}))

          expect(body_for_inner_not).to eq(body_for_outer_not).and query_datastore_with(always_false_condition)
        end

        it "can double negate an `any_of`" do
          inner_filter = {
            "any_of" => [
              {"age" => {"equal_to_any_of" => [25, 30]}},
              {"height" => {"gt" => 10}}
            ]
          }

          query1 = new_query(client_filter: {"not" => {"not" => inner_filter}})
          query2 = new_query(client_filter: inner_filter)

          expect(datastore_body_of(query1)).to eq(datastore_body_of(query2))
        end

        specify "`not: {all_of: [...]}` returns only the documents that are unmatched by `all_of: [...]`" do
          query = new_query(client_filter: {
            "not" => {
              "all_of" => [
                {"age" => {"equal_to_any_of" => [25, 30]}},
                {"height" => {"gt" => 10}}
              ]
            }
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {
            must_not: [{bool: {
              filter: [
                {bool: {filter: [{terms: {"age" => [25, 30]}}]}},
                {bool: {filter: [{range: {"height" => {gt: 10}}}]}}
              ]
            }}]
          }})
        end
      end

      describe "behavior of empty/null filter values" do
        it "treats filtering predicates that are empty no-ops on root fields as `true`" do
          query = new_query(client_filter: {
            "age" => {"gt" => nil},
            "name" => {"equal_to_any_of" => ["Jane"]},
            "height" => {"gte" => nil, "lt" => nil},
            "id" => {}
          })

          expect(datastore_body_of(query)).to filter_datastore_with(terms: {"name" => ["Jane"]})
        end

        it "treats filtering predicates that are empty no-ops on subfields as `true`" do
          query = new_query(client_filter: {
            "bio" => {
              "age" => {"gt" => nil},
              "name" => {"equal_to_any_of" => ["Jane"]},
              "height" => {"gte" => nil, "lt" => nil},
              "id" => {}
            }
          })

          expect(datastore_body_of(query)).to filter_datastore_with(terms: {"bio.name" => ["Jane"]})
        end

        it "does not filter at all when all predicate are empty/null on root fields" do
          query = new_query(client_filter: {
            "age" => {"gt" => nil},
            "name" => {"equal_to_any_of" => nil},
            "height" => {"gte" => nil, "lt" => nil},
            "id" => {}
          })

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "does not filter at all when all predicate are empty/null on subfields" do
          query = new_query(client_filter: {
            "bio" => {
              "age" => {"gt" => nil},
              "name" => {"equal_to_any_of" => nil},
              "height" => {"gte" => nil, "lt" => nil},
              "id" => {}
            }
          })

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "does not prune out `equal_to_any_of: []` to be consistent with `equal_to_any_of` being like an `IN` in SQL and `where field IN ()` should match nothing" do
          query = new_query(client_filter: {
            "name" => {"equal_to_any_of" => []}
          })

          expect(datastore_body_of(query)).to filter_datastore_with(terms: {"name" => []})
        end

        it "returns the standard always false filter for `any_of: []`" do
          query = new_query(client_filter: {
            "any_of" => []
          })

          expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)
        end

        it "returns an always false filter for `any_of: [{any_of: []}]`" do
          query = new_query(client_filter: {
            "any_of" => [{"any_of" => []}]
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {minimum_should_match: 1, should: [
            always_false_condition
          ]}})
        end

        it "does not prune out `any_of: []` to be consistent with `equal_to_any_of: []`, instead providing an 'always false' condition to achieve the same behavior" do
          query = new_query(client_filter: {
            "age" => {"gt" => 18},
            "name" => {"any_of" => []}
          })

          expect(datastore_body_of(query)).to query_datastore_with(bool: {filter: [
            {range: {"age" => {gt: 18}}},
            always_false_condition
          ]})
        end

        it "applies no filtering to an `any_of` composed entirely of empty predicates" do
          query = new_query(client_filter: {
            "age" => {"any_of" => [{"gt" => nil}, {"lt" => nil}]}
          })

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "applies no filtering for an `any_of` composed of an empty predicate and non empty predicate" do
          query = new_query(client_filter: {
            "any_of" => [{"age" => {}}, {"equal_to_any_of" => [36]}]
          })

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "does not filter at all when given only `any_of: nil` on a root field" do
          query = new_query(client_filter: {
            "age" => {"any_of" => nil}
          })

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "does not filter at all when given only `any_of: nil` on a subfield" do
          query = new_query(client_filter: {
            "bio" => {"age" => {"any_of" => nil}}
          })

          expect(datastore_body_of(query)).to not_filter_datastore_at_all
        end

        it "filters to a false condition when given `not: {any_of: {age: nil}}` on a root field" do
          query = new_query(client_filter: {
            "not" => {"any_of" => [{"age" => nil}]}
          })

          expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)
        end

        it "filters to a false condition when given `not: {any_of: nil}` on a sub field" do
          query = new_query(client_filter: {
            "age" => {"not" => {"any_of" => nil}}
          })

          expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)
        end

        it "filters to a true condition when given `not: {any_of: []}` on a sub field" do
          query = new_query(client_filter: {
            "age" => {"not" => {"any_of" => []}}
          })

          expect(datastore_body_of(query)).to query_datastore_with({bool: {must_not: [always_false_condition]}})
        end

        it "filters to a false condition when given `not: {not: {any_of: []}}` on a sub field" do
          query = new_query(client_filter: {
            "age" => {"not" => {"not" => {"any_of" => []}}}
          })

          expect(datastore_body_of(query)).to query_datastore_with(always_false_condition)
        end

        # Note: the GraphQL schema does not allow `any_of: {}` (`any_of` is a list field). However, we're testing
        # it here for completeness--as a defense-in-depth measure, it's good for the filter interpreter to handle
        # whatever is thrown at it. Including these tests allows us to exercise an edge case in the code that
        # can't otherwise be exercised.
        describe "`any_of: {}` (which the GraphQL schema does not allow)" do
          it "does not filter at all when given on a root field" do
            query = new_query(client_filter: {
              "age" => {"any_of" => {}}
            })

            expect(datastore_body_of(query)).to not_filter_datastore_at_all
          end

          it "does not filter at all when given on a subfield" do
            query = new_query(client_filter: {
              "bio" => {"age" => {"any_of" => {}}}
            })

            expect(datastore_body_of(query)).to not_filter_datastore_at_all
          end
        end
      end

      it "uses both `client_filters` and `internal_filters` in the datastore body query when both are provided" do
        query = new_query(
          client_filter: {"age" => {"gt" => 10}},
          internal_filters: [{"some_id" => {"equal_to_any_of" => ["testid"]}}]
        )

        expect(datastore_body_of(query)).to filter_datastore_with(
          {range: {"age" => {gt: 10}}},
          {terms: {"some_id" => ["testid"]}}
#             {bool: {filter: [{range: {"age" => {gt: 10}}}]}},
#             {bool: {filter: [{terms: {"some_id" => ["testid"]}}]}}
        )
      end

      it "uses just `internal_filters` for filtering when no `client_filters` have been provided" do
        query = new_query(
          client_filter: nil,
          internal_filters: [{"some_id" => {"equal_to_any_of" => ["testid"]}}]
        )

        expect(datastore_body_of(query)).to filter_datastore_with(
          {terms: {"some_id" => ["testid"]}}
        )
      end

      def not_filter_datastore_at_all
        exclude(:query)
      end

      def filter_datastore_with(*filters)
        # `filter` uses the datastore's filtering context
        query_datastore_with({bool: {filter: filters}})
      end

      def enum_value(type_name, value_name)
        graphql.schema.type_named(type_name).enum_value_named(value_name)
      end

      def size_of(value_name)
        enum_value("SizeInput", value_name)
      end

      def color_of(value_name)
        enum_value("ColorInput", value_name)
      end

      prepend Module.new {
        def new_query(client_filter:, **options)
          super(client_filters: [client_filter].compact, **options)
        end
      }

      # Custom matcher that provides nicer, more detailed failure output than what built-in RSpec matchers provide.
      matcher :query_datastore_with do |expected_query|
        match do |datastore_body|
          @datastore_body = datastore_body
          @expected_query = expected_query
          expect(datastore_body[:query]).to eq(expected_query)
        end

        # :nocov: -- only covered when an expectation fails
        def expected_json
          @expected_json ||= ::JSON.pretty_generate(normalize(@expected_query))
        end

        def actual_json
          @actual_json ||= ::JSON.pretty_generate(normalize(@datastore_body[:query]))
        end

        failure_message do
          <<~EOS
            Expected `query` in datastore body[^1] to use a specific query[^2].

            [^1] Actual:
            #{actual_json}


            [^2] Expected:
            #{expected_json}


            Diff: #{generate_git_diff}
          EOS
        end

        # RSpec's differ doesn't ignore whitespace, but we want our diffs here to do so to make it easier to read the output.
        def generate_git_diff
          ::Tempfile.create do |expected_file|
            expected_file.write(expected_json + "\n")
            expected_file.fsync

            ::Tempfile.create do |actual_file|
              actual_file.write(actual_json + "\n")
              actual_file.fsync

              `git diff --no-index #{actual_file.path} #{expected_file.path} --ignore-all-space #{" --color" unless ENV["CI"]}`
                .gsub(expected_file.path, "/expected")
                .gsub(actual_file.path, "/actual")
            end
          end
        end

        # We sort hashes by their key so that ordering differences don't show up in the textual diff.
        def normalize(value)
          case value
          when ::Hash
            value.sort_by { |k, v| k.to_s }.to_h { |k, v| [k, normalize(v)] }
          when ::Array
            value.map { |v| normalize(v) }
          else
            value
          end
        end
        # :nocov:
      end
    end
  end
end
