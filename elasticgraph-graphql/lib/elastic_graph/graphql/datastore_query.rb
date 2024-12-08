# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/aggregation/query"
require "elastic_graph/graphql/aggregation/query_optimizer"
require "elastic_graph/graphql/decoded_cursor"
require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/graphql/filtering/filter_interpreter"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  class GraphQL
    # An immutable class that represents a datastore query. Since this represents
    # a datastore query, and not a GraphQL query, all the data in it is modeled
    # in datastore terms, not GraphQL terms. For example, any field names in a
    # `Query` should be references to index fields, not GraphQL fields.
    #
    # Filters are modeled as a `Set` of filtering hashes. While we usually expect only
    # a single `filter` hash, modeling it as a set makes it easy for us to support
    # merging queries. The datastore knows how to apply multiple `must` clauses that
    # apply to the same field, giving us the exact semantics we want in such a situation
    # with minimal effort.
    class DatastoreQuery < Support::MemoizableData.define(
      :total_document_count_needed, :aggregations, :logger, :filter_interpreter, :routing_picker,
      :index_expression_builder, :default_page_size, :search_index_definitions, :max_page_size,
      :filters, :sort, :document_pagination, :requested_fields, :individual_docs_needed,
      :monotonic_clock_deadline, :schema_element_names
    ) {
      def initialize(
        filter: nil,
        filters: nil,
        sort: nil,
        document_pagination: nil,
        aggregations: nil,
        requested_fields: nil,
        individual_docs_needed: false,
        total_document_count_needed: false,
        monotonic_clock_deadline: nil,
        **kwargs
      )
        # Deal with `:filter` vs `:filters` input and normalize it to a single `filters` set.
        filters = ::Set.new(filters || [])
        filters << filter if filter && !filter.empty?
        filters.freeze

        aggregations ||= {}
        requested_fields ||= []

        super(
          filters: filters,
          sort: sort || [],
          document_pagination: document_pagination || {},
          aggregations: aggregations,
          requested_fields: requested_fields.to_set,
          individual_docs_needed: individual_docs_needed || !requested_fields.empty?,
          total_document_count_needed: total_document_count_needed || aggregations.values.any?(&:needs_total_doc_count?),
          monotonic_clock_deadline: monotonic_clock_deadline,
          **kwargs
        )

        if search_index_definitions.empty?
          raise Errors::SearchFailedError, "Query is invalid, since it contains no `search_index_definitions`."
        end
      end
    }
      # Load these files after the `Query` class has been defined, to avoid
      # `TypeError: superclass mismatch for class Query`
      require "elastic_graph/graphql/datastore_query/document_paginator"
      require "elastic_graph/graphql/datastore_query/index_expression_builder"
      require "elastic_graph/graphql/datastore_query/paginator"
      require "elastic_graph/graphql/datastore_query/routing_picker"

      # Performs a list of queries by building a hash of datastore msearch header/body tuples (keyed
      # by query), yielding them to the caller, and then post-processing the results. The caller is
      # responsible for returning a hash of responses by query from its block.
      #
      # Note that some of the passed queries may not be yielded to the caller; when we can tell
      # that a query does not have to be sent to the datastore we avoid yielding it from here.
      # Therefore, the caller should not assume that all queries passed to this method will be
      # yielded back.
      #
      # The return value is a hash of `DatastoreResponse::SearchResponse` objects by query.
      #
      # Note: this method uses `send` to work around ruby visibility rules. We do not want
      # `#decoded_cursor_factory` to be public, as we only need it here, but we cannot access
      # it from a class method without using `send`.
      def self.perform(queries)
        empty_queries, present_queries = queries.partition(&:empty?)

        responses_by_query = Aggregation::QueryOptimizer.optimize_queries(present_queries) do |optimized_queries|
          header_body_tuples_by_query = optimized_queries.each_with_object({}) do |query, hash|
            hash[query] = query.to_datastore_msearch_header_and_body
          end

          yield(header_body_tuples_by_query)
        end

        empty_responses = empty_queries.each_with_object({}) do |query, hash|
          hash[query] = DatastoreResponse::SearchResponse::RAW_EMPTY
        end

        empty_responses.merge(responses_by_query).each_with_object({}) do |(query, response), hash|
          hash[query] = DatastoreResponse::SearchResponse.build(response, decoded_cursor_factory: query.send(:decoded_cursor_factory))
        end.tap do |responses_hash|
          # Callers expect this `perform` method to provide an invariant: the returned hash MUST contain one entry
          # for each of the `queries` passed in the args. In practice, violating this invariant primarily causes a
          # problem when the caller uses the `GraphQL::Dataloader` (which happens for every GraphQL request in production...).
          # However, our tests do not always run queries end-to-end, so this is an added check we want to do, so that
          # anytime our logic here fails to include a query in the response in any test, we'll be notified of the
          # problem.
          expected_queries = queries.to_set
          actual_queries = responses_hash.keys.to_set

          if expected_queries != actual_queries
            missing_queries = expected_queries - actual_queries
            extra_queries = actual_queries - expected_queries

            raise Errors::SearchFailedError, "The `responses_hash` does not have the expected set of queries as keys. " \
              "This can cause problems for the `GraphQL::Dataloader` and suggests a bug in the logic that should be fixed.\n\n" \
              "Missing queries (#{missing_queries.size}):\n#{missing_queries.map(&:inspect).join("\n")}.\n\n" \
              "Extra queries (#{extra_queries.size}): #{extra_queries.map(&:inspect).join("\n")}"
          end
        end
      end

      # Merges the provided query, returning a new combined query object.
      # Both query objects are left unchanged.
      def merge(other_query)
        if search_index_definitions != other_query.search_index_definitions
          raise ElasticGraph::Errors::InvalidMergeError, "`search_index_definitions` conflict while merging between " \
            "#{search_index_definitions} and #{other_query.search_index_definitions}"
        end

        with(
          individual_docs_needed: individual_docs_needed || other_query.individual_docs_needed,
          total_document_count_needed: total_document_count_needed || other_query.total_document_count_needed,
          filters: filters + other_query.filters,
          sort: merge_attribute(other_query, :sort),
          requested_fields: requested_fields + other_query.requested_fields,
          document_pagination: merge_attribute(other_query, :document_pagination),
          monotonic_clock_deadline: [monotonic_clock_deadline, other_query.monotonic_clock_deadline].compact.min,
          aggregations: aggregations.merge(other_query.aggregations)
        )
      end

      # Convenience method for merging when you do not have access to an
      # `DatastoreQuery::Builder`. Allows you to pass the query options you
      # would like to merge. As with `#merge`, leaves the original query unchanged
      # and returns a combined query object.
      def merge_with(**query_options)
        merge(with(**query_options))
      end

      # Pairs the multi-search headers and body into a tuple, as per the format required by the datastore:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/search-multi-search.html#search-multi-search-api-desc
      def to_datastore_msearch_header_and_body
        @to_datastore_msearch_header_and_body ||= [to_datastore_msearch_header, to_datastore_body]
      end

      # Returns an index_definition expression string to use for searches. This string can specify
      # multiple indices, use wildcards, etc. For info about what is supported, see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/multi-index.html
      def search_index_expression
        @search_index_expression ||= index_expression_builder.determine_search_index_expression(
          filters,
          search_index_definitions,
          # When we have aggregations, we must require indices to search. When we search no indices, the datastore does not return
          # the standard aggregations response structure, which causes problems.
          require_indices: !aggregations_datastore_body.empty?
        ).to_s
      end

      # Returns the name of the datastore cluster as a String where this query should be setn.
      # Unless exactly 1 cluster name is found, this method raises a Errors::ConfigError.
      def cluster_name
        cluster_name = search_index_definitions.map(&:cluster_to_query).uniq
        return cluster_name.first if cluster_name.size == 1
        raise Errors::ConfigError, "Found different datastore clusters (#{cluster_name}) to query " \
          "for query targeting indices: #{search_index_definitions}"
      end

      # Returns a list of unique field paths that should be used for shard routing during searches.
      #
      # If a search is filtering on one of these fields, we can optimize the search by routing
      # it to only the shards containing documents for that routing value.
      #
      # Note that this returns a list due to our support for type unions. A unioned type
      # can be composed of subtypes that have use different shard routing; this will return
      # the set union of them all.
      def route_with_field_paths
        search_index_definitions.map(&:route_with).uniq
      end

      # The shard routing values used for this search. Can be `nil` if the query will hit all shards.
      # `[]` means that we are routing to no shards.
      def shard_routing_values
        return @shard_routing_values if defined?(@shard_routing_values)
        routing_values = routing_picker.extract_eligible_routing_values(filters, route_with_field_paths)

        @shard_routing_values ||=
          if routing_values&.empty? && !aggregations_datastore_body.empty?
            # If we return an empty array of routing values, no shards will get searched, which causes a problem for aggregations.
            # When a query includes aggregations, there are normally aggregation structures on the respopnse (even when there are no
            # search hits to aggregate over!) but if there are no routing values, those aggregation structures will be missing from
            # the response. It's complex to handle that in our downstream response handling code, so we prefer to force a "fallback"
            # routing value here to ensure that at least one shard gets searched. Which shard gets searched doesn't matter; the search
            # filter that led to an empty set of routing values will match on documents on any shard.
            ["fallback_shard_routing_value"]
          elsif contains_ignored_values_for_routing?(routing_values)
            nil
          else
            routing_values&.sort # order doesn't matter, but sorting it makes it easier to assert on in our tests.
          end
      end

      # Indicates if the query does not need any results from the datastore. As an optimization,
      # we can reply with a default "empty" response for an empty query.
      def empty?
        # If we are searching no indices or routing to an empty set of shards, there is no need to query the datastore at all.
        # This only happens when our filter processing has deduced that the query will match no results.
        return true if search_index_expression.empty? || shard_routing_values&.empty?

        datastore_body = to_datastore_body
        datastore_body.fetch(:size) == 0 && !datastore_body.fetch(:track_total_hits) && aggregations_datastore_body.empty?
      end

      def inspect
        description = to_datastore_msearch_header.merge(to_datastore_body).map do |key, value|
          "#{key}=#{(key == :query) ? "<REDACTED>" : value.inspect}"
        end.join(" ")

        "#<#{self.class.name} #{description}>"
      end

      def to_datastore_msearch_header
        @to_datastore_msearch_header ||= {index: search_index_expression, routing: shard_routing_values&.join(",")}.compact
      end

      # `DatastoreQuery` objects are used as keys in a hash. Computing `#hash` can be expensive (given how many fields
      # an `DatastoreQuery` has) and it's safe to cache since `DatastoreQuery` instances are immutable, so we memoize it
      # here. We've observed this making a very noticeable difference in our test suite runtime.
      def hash
        @hash ||= super
      end

      def document_paginator
        @document_paginator ||= DocumentPaginator.new(
          sort_clauses: sort_with_tiebreaker,
          individual_docs_needed: individual_docs_needed,
          total_document_count_needed: total_document_count_needed,
          decoded_cursor_factory: decoded_cursor_factory,
          schema_element_names: schema_element_names,
          paginator: Paginator.new(
            default_page_size: default_page_size,
            max_page_size: max_page_size,
            first: document_pagination[:first],
            after: document_pagination[:after],
            last: document_pagination[:last],
            before: document_pagination[:before],
            schema_element_names: schema_element_names
          )
        )
      end

      private

      def merge_attribute(other_query, attribute)
        value = public_send(attribute)
        other_value = other_query.public_send(attribute)

        if value.empty?
          other_value
        elsif other_value.empty?
          value
        elsif value == other_value
          value
        else
          logger.warn("Tried to merge two queries that both define `#{attribute}`, using the value from the query being merged: #{value}, #{other_value}")
          other_value
        end
      end

      TIEBREAKER_SORT_CLAUSES = [{"id" => {"order" => "asc"}}].freeze

      # We want to use `id` as a tiebreaker ONLY when `id` isn't explicitly specified as a sort field
      def sort_with_tiebreaker
        @sort_with_tiebreaker ||= remove_duplicate_sort_clauses(sort + TIEBREAKER_SORT_CLAUSES)
      end

      def remove_duplicate_sort_clauses(sort_clauses)
        seen_fields = Set.new
        sort_clauses.select do |clause|
          clause.keys.all? { |key| seen_fields.add?(key) }
        end
      end

      def decoded_cursor_factory
        @decoded_cursor_factory ||= DecodedCursor::Factory.from_sort_list(sort_with_tiebreaker)
      end

      def contains_ignored_values_for_routing?(routing_values)
        ignored_values_for_routing.intersect?(routing_values.to_set) if routing_values
      end

      def ignored_values_for_routing
        @ignored_values_for_routing ||= search_index_definitions.flat_map { |i| i.ignored_values_for_routing.to_a }.to_set
      end

      def to_datastore_body
        @to_datastore_body ||= aggregations_datastore_body
          .merge(document_paginator.to_datastore_body)
          .merge({query: filter_interpreter.build_query(filters)}.compact)
          .merge({_source: source})
      end

      def aggregations_datastore_body
        @aggregations_datastore_body ||= begin
          aggs = aggregations
            .values
            .map { |agg| agg.build_agg_hash(filter_interpreter) }
            .reduce({}, :merge)

          aggs.empty? ? {} : {aggs: aggs}
        end
      end

      # Make our query as efficient as possible by limiting what parts of `_source` we fetch.
      # For an id-only query (or a query that has no requested fields) we don't need to fetch `_source`
      # at all--which means the datastore can avoid decompressing the _source field. Otherwise,
      # we only ask for the fields we need to return.
      def source
        requested_source_fields = requested_fields - ["id"]
        return false if requested_source_fields.empty?
        # Merging in requested_fields as _source:{includes:} based on Elasticsearch documentation:
        # https://www.elastic.co/guide/en/elasticsearch/reference/current/mapping-source-field.html#include-exclude
        {includes: requested_source_fields.to_a}
      end

      # Encapsulates dependencies of `Query`, giving us something we can expose off of `application`
      # to build queries when desired.
      class Builder < Support::MemoizableData.define(:runtime_metadata, :logger, :filter_node_interpreter, :query_defaults)
        def self.with(runtime_metadata:, logger:, filter_node_interpreter:, **query_defaults)
          new(runtime_metadata:, logger:, filter_node_interpreter:, query_defaults:)
        end

        def routing_picker
          @routing_picker ||= RoutingPicker.new(
            filter_node_interpreter: filter_node_interpreter,
            schema_names: runtime_metadata.schema_element_names
          )
        end

        def index_expression_builder
          @index_expression_builder ||= IndexExpressionBuilder.new(
            filter_node_interpreter: filter_node_interpreter,
            schema_names: runtime_metadata.schema_element_names
          )
        end

        def new_query(**options)
          DatastoreQuery.new(
            routing_picker: routing_picker,
            index_expression_builder: index_expression_builder,
            logger: logger,
            schema_element_names: runtime_metadata.schema_element_names,
            **query_defaults.merge(options)
          )
        end
      end
    end
  end
end
