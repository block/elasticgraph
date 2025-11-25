# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/filtering/field_path"
require "elastic_graph/graphql/filtering/filter_node_interpreter"
require "elastic_graph/support/graphql_formatter"
require "elastic_graph/support/memoizable_data"
require "graphql"

module ElasticGraph
  class GraphQL
    module Filtering
      # Responsible for interpreting a query's overall `filter`. Not tested directly; tests drive the `Query` interface instead.
      #
      # For more info on how this works, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html
      # https://www.elastic.co/blog/lost-in-translation-boolean-operations-and-filters-in-the-bool-query
      FilterInterpreter = Support::MemoizableData.define(:filter_node_interpreter, :schema_names, :logger) do
        # @implements FilterInterpreter

        def initialize(filter_node_interpreter:, logger:)
          super(
            filter_node_interpreter: filter_node_interpreter,
            schema_names: filter_node_interpreter.schema_names,
            logger: logger
          )
        end

        # Builds a datastore query from the given collection of filter hashes.
        #
        # Returns `nil` if there are no query clauses, to make it easy for a caller to `compact` out
        # `query: {}` in a larger search request body.
        #
        # https://www.elastic.co/guide/en/elasticsearch/reference/8.11/query-dsl.html
        def build_query(filter_hashes, from_field_path: FieldPath.empty)
          build_bool_hash do |bool_node|
            filter_hashes.each do |filter_hash|
              process_filter_hash(bool_node, filter_hash, from_field_path)
            end
          end
        end

        def to_s
          # The inspect/to_s output of `filter_node_interpreter` and `logger` can be quite large and noisy. We generally don't care about
          # those details but want to be able to tell at a glance if two `FilterInterpreter` instances are equal or not--and, if they
          # aren't equal, which part is responsible for the inequality.
          #
          # Using the hash of the two initialize args provides us with that.
          "#<data #{FilterInterpreter.name} filter_node_interpreter=(hash: #{filter_node_interpreter.hash}) logger=(hash: #{logger.hash})>"
        end
        alias_method :inspect, :to_s

        private

        def process_filter_hash(bool_node, filter_hash, field_path)
          filter_hash.each do |field_or_op, expression|
            case filter_node_interpreter.identify_node_type(field_or_op, expression)
            when :empty
              # This is an "empty" filter predicate and can be treated as `true`.
            when :not
              process_not_expression(bool_node, expression, field_path)
            when :list_any_filter
              process_list_any_filter_expression(bool_node, expression, field_path)
            when :any_of
              process_any_of_expression(bool_node, expression, field_path)
            when :all_of
              process_all_of_expression(bool_node, expression, field_path)
            when :operator
              process_operator_expression(bool_node, field_or_op, expression, field_path)
            when :list_count
              process_list_count_expression(bool_node, expression, field_path)
            when :sub_field
              process_sub_field_expression(bool_node, expression, field_path + field_or_op)
            else
              logger.warn("Ignoring unknown filtering operator (#{field_or_op}: #{expression.inspect}) on field `#{field_path.from_root.join(".")}`")
            end
          end
        end

        # Indicates if the given `expression` applies filtering to subfields or just applies
        # operators at the current field path.
        def filters_on_sub_fields?(expression)
          expression.any? do |field_or_op, sub_expression|
            case filter_node_interpreter.identify_node_type(field_or_op, sub_expression)
            when :sub_field
              true
            when :not, :list_any_filter
              filters_on_sub_fields?(sub_expression)
            when :any_of, :all_of
              # These are the only two cases where the `sub_expression` is an array of filter sub expressions,
              # so we use `.any?` on it here. (Even for `all_of`--the overall `expression` filters on sub fields so
              # long as at least one of the sub expressions does, regardless of it being `any_of` vs `all_of`).
              sub_expression.any? { |expr| filters_on_sub_fields?(expr) }
            else # :empty, :operator, :unknown, :list_count
              false
            end
          end
        end

        def process_not_expression(bool_node, expression, field_path)
          sub_filter = build_bool_hash do |inner_node|
            process_filter_hash(inner_node, expression || {}, field_path)
          end

          unless sub_filter
            # Since an empty expression is treated as `true`, convert to `false` when negating.
            BooleanQuery::ALWAYS_FALSE_FILTER.merge_into(bool_node)
            return
          end

          # Prevent any negated filters from being unnecessarily double-negated by
          # converting them to a positive filter (i.e., !!A == A).
          if sub_filter[:bool].key?(:must_not)
            # Pull clauses up to current bool_node to remove negation
            sub_filter[:bool][:must_not].each do |negated_clause|
              negated_clause_bool = negated_clause[:bool]
              # `minimum_should_match` is not a list like the other clauses, and needs to be handled separately.
              negated_clause_bool.except(:minimum_should_match).each { |k, v| bool_node[k].concat(v) }
              if (min_should_match = negated_clause_bool[:minimum_should_match])
                bool_node[:minimum_should_match] = min_should_match
              end
            end
          end

          # Don't drop any other filters! Let's negate them now.
          other_filters = sub_filter[:bool].except(:must_not)
          bool_node[:must_not] << {bool: other_filters} unless other_filters.empty?
        end

        # There are two cases for `any_satisfy`, each of which is handled differently:
        #
        # - List-of-scalars
        # - List-of-nested-objects
        #
        # We can detect which it is by checking `filter` to see if it filters on any subfields.
        # If so, we know the filter is being applied to a `nested` list field. We can count on
        # this because we do not generate `any_satisfy` filters on `object` list fields (instead,
        # they get generated on their leaf fields).
        def process_list_any_filter_expression(bool_node, filter, field_path)
          if filters_on_sub_fields?(filter)
            process_any_satisfy_filter_expression_on_nested_object_list(bool_node, filter, field_path)
          else
            process_any_satisfy_filter_expression_on_scalar_list(bool_node, filter, field_path)
          end
        end

        def process_any_satisfy_filter_expression_on_nested_object_list(bool_node, filter, field_path)
          sub_filter = build_bool_hash do |inner_node|
            process_filter_hash(inner_node, filter, field_path.nested)
          end

          if sub_filter
            bool_node[:filter] << {nested: {path: field_path.from_root.join("."), query: sub_filter}}
          end
        end

        # On a list-of-leaf-values field, `any_satisfy` doesn't _do_ anything: it just expresses
        # the fact that documents with any list element values matching the predicates will match
        # the overall filter.
        def process_any_satisfy_filter_expression_on_scalar_list(bool_node, filter, field_path)
          return unless (processed = build_bool_hash { |node| process_filter_hash(node, filter, field_path) })

          processed_bool_query = processed.fetch(:bool)

          # The semantics we want for `any_satisfy` are that it matches when a value exists in the list that
          # satisfies all of the provided subfilter. That's the semantics the datastore provides when the bool
          # query only requires one clause to match, but if multiple clauses are required to match there's a subtle
          # issue. A document matches so long as each required clause matches *some* value, but it doesn't require
          # that they all match the *same* value. The list field on a document could contain N values, where
          # each value matches a different one of the required clauses, and the document will be a search hit.
          #
          # Rather than behaving in a surprising way here, we'd rather disallow a filter that has multiple required
          # clauses, so we return an error in this case.
          if required_matching_clause_count(processed_bool_query) > 1
            formatted_filter = Support::GraphQLFormatter.serialize(
              {schema_names.any_satisfy => filter},
              wrap_hash_with_braces: false
            )

            raise ::GraphQL::ExecutionError, "`#{formatted_filter}` is not supported because it produces " \
              "multiple filtering clauses under `#{schema_names.any_satisfy}`, which doesn't work as expected. " \
              "Remove one or more of your `#{schema_names.any_satisfy}` predicates and try again."
          else
            bool_node.update(processed_bool_query) do |_, existing_clauses, any_satisfy_clauses|
              existing_clauses + any_satisfy_clauses
            end
          end
        end

        # We want to provide the following semantics for `any_of`:
        #
        # * `filter: {anyOf: []}` -> return no results
        # * `filter: {anyOf: [{field: null}]}` -> return all results
        # * `filter: {anyOf: [{field: null}, {field: ...}]}` -> return all results
        def process_any_of_expression(bool_node, expressions, field_path)
          if expressions.empty?
            # When our `expressions` array is empty, we want to match no documents. However, that's
            # not the behavior the datastore will give us if we have an empty array in the query under
            # `should`. To get the behavior we want, we need to pass the datastore some filter criteria
            # that will evaluate to false for every document.
            BooleanQuery::ALWAYS_FALSE_FILTER.merge_into(bool_node)
            return
          end

          shoulds = expressions.filter_map do |expression|
            build_bool_hash do |inner_bool_node|
              process_filter_hash(inner_bool_node, expression, field_path)
            end
          end

          return if shoulds.size < expressions.size

          BooleanQuery.should(*shoulds).merge_into(bool_node)
        end

        def process_all_of_expression(bool_node, expressions, field_path)
          # `all_of` represents an AND of multiple subexpressions.
          # To achieve this, we build a new bool sub-filter for each subexpression and push it onto
          # the parent’s `:filter` array. Each item in `:filter` is independently required (AND).
          expressions.each do |sub_expression|
            sub_filter = build_bool_hash do |sub_bool_node|
              process_filter_hash(sub_bool_node, sub_expression, field_path)
            end
            bool_node[:filter] << sub_filter if sub_filter
          end
        end

        def process_operator_expression(bool_node, operator, expression, field_path)
          # `operator` is a filtering operator, and `expression` is the value the filtering
          # operator should be applied to. The `op_applicator` lambda, when called, will
          # return a Clause instance (defined in this module).
          bool_query = filter_node_interpreter.filter_operators.fetch(operator).call(field_path.from_root.join("."), expression)
          bool_query&.merge_into(bool_node)
        end

        def process_sub_field_expression(bool_node, expression, field_path)
          # `sub_field` is a field name, and `expression` is a hash of filters to apply to that field.
          # We want to add the field name to the field path and recursively process the hash.
          #
          # However, if the hash has `any_of` in it, then we need to process the filter hash on
          # a nested bool node instead of on the `bool_node` we are already operating on.
          #
          # To understand why, first consider a filter that has no `any_of` but does use field nesting:
          #
          # filter: {
          #   weight: {lt: 2000},
          #   cost: {
          #     currency: {equal_to_any_of: ["USD"]}
          #     amount: {gt: 1000}
          #   }
          # }
          #
          # While this `currency` and `amount` are expressed as sub-filters under `cost` in our GraphQL
          # syntax, we do not actually need to create a nested bool node structure for the datastore
          # query. We get a flat filter structure like this:
          #
          # {bool: {filter: [
          #   {range: {"weight": {lt: 2000}}},
          #   {terms: {"cost.currency": ["USD"]}},
          #   {range: {"amount": {gt: 1000}}}
          # ]}}
          #
          # The 3 filter conditions are ANDed together as a single list under `filter`.
          # The nested field structure gets flattened using a dot-separated path.
          #
          # Now consider a filter that has multiple `any_of` sub-expressions:
          #
          # filter: {
          #   weight: {any_of: [
          #     {gt: 9000},
          #     {lt: 2000}
          #   ]},
          #   cost: {any_of: [
          #     currency: {equal_to_any_of: ["USD"]},
          #     amount: {gt: 1000}
          #   ]}
          # }
          #
          # If we did not make a nested structure, we would wind up with a single list of sub-expressions
          # that are OR'd together:
          #
          # {bool: {filter: [{bool: {should: [
          #   {range: {"weight": {gt: 9000}}},
          #   {range: {"weight": {lt: 2000}}},
          #   {terms: {"cost.currency": ["USD"]}},
          #   {range: {"amount": {gt: 1000}}}
          # ]}}]}}
          #
          # ...but that's clearly wrong. By creating a nested bool node based on the presence of `any_of`,
          # we can instead produce a structure like this:
          #
          # {bool: {filter: [
          #   {bool: {should: [
          #     {range: {"weight": {gt: 9000}}},
          #     {range: {"weight": {lt: 2000}}}
          #   ]}},
          #   {bool: {should: [
          #     {terms: {"cost.currency": ["USD"]}},
          #     {range: {"amount": {gt: 1000}}}
          #   ]}}
          # ]}}
          #
          # ...which will actually work correctly.
          if expression.key?(schema_names.any_of)
            sub_filter = build_bool_hash do |inner_node|
              process_filter_hash(inner_node, expression, field_path)
            end

            bool_node[:filter] << sub_filter if sub_filter
          else
            process_filter_hash(bool_node, expression, field_path)
          end
        end

        def process_list_count_expression(bool_node, expression, field_path)
          # Normally, we don't have to do anything special for list count expressions.
          # That's the case, for example, for an expression like:
          #
          # filter: {tags: {count: {gt: 2}}}
          #
          # However, if the count expression could match count of 0 (that is, if it doesn't
          # exclude a count of zero), such as this:
          #
          # filter: {tags: {count: {lt: 1}}}
          #
          # ...then we need some special handling here. A count of 0 is equivalent to the list field not existing.
          # While we index an explicit count of 0, the count field will be missing from documents indexed before
          # the list field was defined on the ElasticGraph schema. To properly match those documents, we need to
          # convert this into an OR (using `any_of`) to also match documents that lack the field entirely.
          if filters_to_range_including_zero?(expression)
            expression = {schema_names.any_of => [
              expression,
              {schema_names.equal_to_any_of => [nil]}
            ]}
          end

          process_sub_field_expression(bool_node, expression, field_path.counts_path)
        end

        def build_bool_hash(&block)
          bool_node = Hash.new { |h, k| h[k] = [] } # : stringOrSymbolHash
          bool_node.tap(&block)

          # To treat "empty" filter predicates as `true` we need to return `nil` here.
          return nil if bool_node.empty?

          # According to https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html#bool-min-should-match,
          # if the bool query includes at least one should clause and no must or filter clauses, the default value is 1. Otherwise, the default value is 0.
          # However, we want should clauses to work with musts and filters, so we need to set it explicitly to 1 when we have should clauses.
          bool_node[:minimum_should_match] = 1 if bool_node.key?(:should)

          {bool: bool_node}
        end

        # Determines if the given expression filters to a range that includes `0`.
        # If it does not do any filtering (e.g. an empty expression) it will return `false`.
        def filters_to_range_including_zero?(expression)
          expression = expression.compact

          expression.size > 0 && expression.none? do |operator, operand|
            operator_excludes_zero?(operator, operand)
          end
        end

        # Determines if the given operator and operand exclude 0 as a matched value.
        def operator_excludes_zero?(operator, operand)
          case operator
          when schema_names.equal_to_any_of then !operand.include?(0)
          when schema_names.lt then operand <= 0
          when schema_names.lte then operand < 0
          when schema_names.gt then operand >= 0
          when schema_names.gte then operand > 0
          else
            # :nocov: -- all operators are covered above. But simplecov complains about an implicit `else` branch being uncovered, so here we've defined it to wrap it with `:nocov:`.
            false
            # :nocov:
          end
        end

        # Counts how many clauses in `bool_query` are required to match for a document to be a search hit.
        def required_matching_clause_count(bool_query)
          bool_query.reduce(0) do |count, (occurrence, clauses)|
            case occurrence
            when :should
              # The number of required matching clauses imposed by `:should` depends on the `:minimum_should_match` value.
              # https://www.elastic.co/guide/en/elasticsearch/reference/8.9/query-dsl-bool-query.html#bool-min-should-match
              bool_query.fetch(:minimum_should_match)
            when :minimum_should_match
              0 # doesn't have any clauses on its own, just controls how many `:should` clauses are required.
            else
              # For all other occurrences, each cluse must match.
              clauses.size
            end + count
          end
        end
      end
    end
  end
end
