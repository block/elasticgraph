# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/resolvers/query_source"

module ElasticGraph
  class GraphQL
    module Resolvers
      # A GraphQL dataloader responsible for solving a thorny N+1 query problem related to our `NestedRelationships` resolver.
      # The `QuerySource` dataloader implements a basic batching optimization: multiple datastore queries are batched up into
      # a single `msearch` call against the dataastore. This is significantly better than submitting a separate request per
      # query, but is still not optimal--the datastore still must execute N different queries, which could cause significant load.
      #
      # A significantly improved optimization is possible in one particular situation from our `NestedRelationships` resolver.
      # Here's an example of that situation:
      #
      #   - `Part` documents are indexed in a `parts` index and `Manufacturer` documents are indexed in a `manufacturers` index.
      #   - `Part.manufacturer` is defined as: `t.relates_to_one "manufacturer", "Manufacturer", via: "manufacturer_id", dir: :out`.
      #   - We are processing a GraphQL query like this: `parts(first: 10) { nodes { manufacturer { name } } }`.
      #   - For each of the 10 parts, the `NestedRelationships` resolver has to resolve its related `Part.manufacturer`.
      #   - Without the optimization provided by this class, `NestedRelationships` would have to execute 10 different queries,
      #     each of which is identical except for a different filter: `{id: {equal_to_any_of: [part.manufacturer_id]}}`.
      #   - Instead of executing this as 10 different queries, we can instead execute it as one query with this combined filter:
      #     `{id: {equal_to_any_of: [part1.manufacturer_id, ..., part10.manufacturer_id]}}`
      #   - When we do this, we get a single response, but `NestedRelationships` expects a separate response for each one.
      #   - To satisfy that, we can split the single response into 10 different responses (one per filter).
      #
      # This optimization, when we can apply it, results in much less load on the datastore. In addition, it also helps to reduce
      # the amount of overhead imposed by ElasticGraph. Profiling has shown that significant overhead is incurred when we repeatedly
      # merge filters into a query (e.g. `query.merge_with(filters: [{id: {equal_to_any_of: [part.manufacturer_id]}}])` 10 times to
      # produce 10 different queries). This optimization also avoids that overhead.
      #
      # Note: while the comments discuss the examples in terms of _parent objects_, in the implementation, we deal with id sets.
      # A set of ids is contributed by each parent object.
      class NestedRelationshipsSource < ::GraphQL::Dataloader::Source
        # The optimization implemented by this class is not guaranteed to get all expected results in a single query for cases where
        # the sorted search results are not well-distributed among each of the parent objects while we're resolving a `relates_to_many`
        # field. (See the comments on `fetch_via_single_query_with_merged_filters` for a detailed description of when this occurs).
        #
        # To deal with this situation, we retry the query for just the parent objects which may have incomplete results. However,
        # each attempt is run in serial, and we want to put a strict upper bound on how many attempts are made. This constant defines
        # the maximum number of optimized attempts we allow.
        #
        # When exceeded, we fall back to building and executing a separate query (via a single `msearch` request) for each parent object.
        MAX_OPTIMIZED_ATTEMPTS = 3

        # Reattempts are less likely to be needed when we execute the query with a larger `size`, because we are more likely to get back
        # complete results for each parent object. This multiplier is applied to the requested size to achieve that.
        #
        # 4 was chosen somewhat arbitrarily, but should make reattempts needed much less often while avoiding asking for an unreasonably
        # large number of results.
        #
        # Note: asking the datastore for a larger `size` is quite a bit more efficient than needing to execute more queries.
        # Once the datastore has gone to the spot in its inverted index with the matching documents, asking for more results
        # isn't particularly expensive, compared to needing to re-run an extra query.
        EXTRA_SIZE_MULTIPLIER = 4

        def initialize(query:, join:, context:, monotonic_clock:, mode:)
          @query = query
          @join = join
          @filter_id_field_name_path = @join.filter_id_field_name.split(".")
          @context = context
          @schema_element_names = @context.fetch(:schema_element_names)
          @logger = context.fetch(:logger)
          @monotonic_clock = monotonic_clock
          @mode = mode
        end

        def fetch(id_sets)
          return fetch_original(id_sets) unless can_merge_filters?

          case @mode
          when :original
            fetch_original(id_sets)
          when :comparison
            fetch_comparison(id_sets)
          else
            fetch_optimized(id_sets)
          end
        end

        def self.execute_one(ids, query:, join:, context:, monotonic_clock:, mode:)
          context.dataloader.with(self, query:, join:, context:, monotonic_clock:, mode:).load(ids)
        end

        private

        def fetch_optimized(id_sets)
          attempt_count = 0
          duration_ms, responses_by_id_set = time_duration do
            fetch_via_single_query_with_merged_filters(id_sets) { attempt_count += 1 }
          end

          if id_sets.size > 1
            @logger.info({
              "message_type" => "NestedRelationshipsMergedQueries",
              "field" => @join.field.description,
              "optimized_attempt_count" => [attempt_count, MAX_OPTIMIZED_ATTEMPTS].min,
              "degraded_to_separate_queries" => (attempt_count > MAX_OPTIMIZED_ATTEMPTS),
              "id_set_count" => id_sets.size,
              "total_id_count" => id_sets.reduce(:union).size,
              "duration_ms" => duration_ms
            })
          end

          id_sets.map { |id_set| responses_by_id_set.fetch(id_set) }
        end

        def fetch_original(id_sets, requested_fields: [])
          fetch_via_separate_queries(id_sets, requested_fields: requested_fields)
        end

        def fetch_comparison(id_sets)
          # Note: we'd ideally run both versions of the logic in parallel, but our attempts to do that resulted in errors
          # because of the fiber context in which dataloaders run.
          original_duration_ms, original_results = time_duration do
            # In the `fetch_optimized` implementation, we request this extra field. We don't need it for
            # the original implementation (so `fetch_original` doesn't also request that field...) but for
            # the purposes of comparison we need to request it so that the document payloads will have the
            # same fields.
            #
            # Note: we don't add the requested field if we have only a single id set, in order to align with
            # the short-circuiting logic in `fetch_via_single_query_with_merged_filters`. Otherwise, any time
            # we have a single id set we always get reported differences which are not actually real!
            requested_fields = (id_sets.size > 1) ? [@join.filter_id_field_name] : [] # : ::Array[::String]
            fetch_original(id_sets, requested_fields: requested_fields)
          end

          optimized_duration_ms, optimized_results = time_duration do
            fetch_optimized(id_sets)
          end

          # To see if we got the same results we only look at the documents, because we expect differences outside
          # of the documents--for example, the `SearchResponse#metadata` will report different `took` values.
          got_same_results = original_results.map(&:documents) == optimized_results.map(&:documents)
          message = {
            "message_type" => "NestedRelationshipsComparisonResults",
            "field" => @join.field.description,
            "original_duration_ms" => original_duration_ms,
            "optimized_duration_ms" => optimized_duration_ms,
            "optimized_faster" => (optimized_duration_ms < original_duration_ms),
            "id_set_count" => id_sets.size,
            "total_id_count" => id_sets.reduce(:union).size,
            "got_same_results" => got_same_results
          }

          if got_same_results
            @logger.info(message)
          else
            @logger.error(message.merge({
              "original_documents" => loggable_results(original_results),
              "optimized_documents" => loggable_results(optimized_results)
            }))
          end

          original_results
        end

        # For "simple", document-based queries, we can safely merge filters. However, this cannot be done safely when the response
        # cannot safely be "pulled part" into the bits that apply to a particular set of ids for a parent object. Specifically:
        #
        #   - If `total_document_count_needed` is true, we can't merge filters, because there's no way to get a separate count
        #     for each parent object unless we execute separate queries (or combine them into a grouped aggregation count query,
        #     but that requires a much more challenging transformation of the query and response).
        #   - If the query has any `aggregations`, we likewise can't merge the filters, because we have no way to "pull apart"
        #     the aggregations response.
        def can_merge_filters?
          !@query.total_document_count_needed && @query.aggregations.empty?
        end

        # Executes a single query that contains a merged filter from the set union of the given `id_sets`.
        # This merged query is (theoretically) capable of getting all the results we're looking for in a
        # single query, which is much more efficient than building and performing a separate query for each
        # id set. We can use `search_response.filter_results(id_set)` with each id set to get a
        # response with the documents filtered down to just the ones that match the id set. (Essentially,
        # this is the response we would have gotten if we had executed a separate query for the id set).
        #
        # However, it is not guaranteed that we will get back complete results with this approach. Consider this example:
        #
        #   - The datastore has 50 documents that match `id_set_1`, and 50 that match `id_set_2`.
        #   - The requested size of `@query` is 10 (meaning the client expects the first 10 results matching `id_set_1` and
        #     the first 10 results matching `id_set_2).
        #   - All 50 documents that match `id_set_1` sort before all 50 documents that match `id_set_2`.
        #   - When we execute our merged query filtering on the `union(id_set_1, id_set_2)` set, we ask for
        #     20 documents (since we want 10 for `id_set_1` and 10 for `id_set_2`).
        #   - ...but we get back 20 documents for `id_set_1` and 0 documents for `id_set_2`.
        #
        # There is no way to guarantee that we get back the desired number of results for each id set unless we build and
        # execute a separate query per id set, which is inefficient (in some situations, it causes one GraphQL query to
        # execute hundreds of queries against the datastore!).
        #
        # To deal with this possibility, this method takes an iterative approach:
        #
        #   - It builds and executes an initial optimized merged query, with a large `size_multiplier` which gives us a good bit of
        #     "headroom" for this kind of situation. In the example above, if we requested 60 results from the datastore, we'd be
        #     able to get the 10 results for both id sets we are looking for--50 for `id_set_1` nad 10 for `id_set_2`.
        #   - It then inspects the response. If the datastore returned fewer results than we asked for, then there are no missing
        #     results and we can trust that we got all the results we would have gotten if we had executed a separate query per
        #     id set.
        #   - If we got back the number of results we asked for, then it's possible that we've run into this situation. We need
        #     to inspect each filtered response produced for each id set to see if more results were expected.
        #     - Note: the fact that more results were expected doesn't necessarily mean there are more results. But we have no way
        #       to tell for sure without querying the datastore again, so we err on the side of safety and treat this kind of response
        #       as being incomplete.
        #   - For each id set that appears to be incomplete, we try again. But on the next attempt, we exclude the id sets
        #     which got a complete set of results.
        #   - This may cause us to iterate a couple of times (which could make the single GraphQL query we are processing slower than
        #     it would have been without this optimization, particularly if the datastore was not under any other load...) but we expect
        #     it to make a big difference in the amount of load we put on the datastore, and that helps _all_ query traffic to be more
        #     performant overall.
        def fetch_via_single_query_with_merged_filters(id_sets, remaining_attempts: MAX_OPTIMIZED_ATTEMPTS)
          yield # yield to signal an attempt

          # Fallback to executing separate queries when one of the following occurs:
          #
          #   - We lack multiple sets of ids.
          #   - We have exhausted our MAX_OPTIMIZED_ATTEMPTS.
          if id_sets.size < 2 || remaining_attempts < 1
            return id_sets.zip(fetch_via_separate_queries(id_sets)).to_h
          end

          # First, we build a combined query with filters that account for all ids we are filtering on from all `id_sets`.
          filtered_query = @query.merge_with(
            filters: filters_for(id_sets.reduce(:union)),
            requested_fields: [@join.filter_id_field_name],
            # We need to request a larger size than `@query` originally had. If the original size was `10` and we have
            # 5 sets of ids, then, at a minimum, we need to request 50 results (10 results for each id set).
            #
            # In addition, we apply `EXTRA_SIZE_MULTIPLIER` to increase the size further and make it less likely that
            # we we get incomplete results and have to retry.
            size_multiplier: id_sets.size * EXTRA_SIZE_MULTIPLIER
          )

          # Then we execute that combined query.
          response = QuerySource.execute_one(filtered_query, for_context: @context)

          # Next, we produce a separate response for each id set by filtering the results to the ones that match the ids in the set.
          filtered_responses_by_id_set = id_sets.to_h do |id_set|
            filtered_response = response.filter_results(@filter_id_field_name_path, id_set, @query.effective_size)
            [id_set, filtered_response]
          end

          # If our merged/filtered query got back fewer results than we requested, then no matching results are missing,
          # and we know that we've gotten complete results for all id sets.
          if response.size < filtered_query.effective_size
            return filtered_responses_by_id_set
          end

          # Since our `filtered_query` got back as many results as we asked for, there may be additional matching results that
          # were not returned, and some id sets may have gotten fewer results than requested by the client.
          # Here we determine which id sets that applies to.
          id_sets_with_apparently_incomplete_results = filtered_responses_by_id_set.filter_map do |id_set, filtered_response|
            id_set if filtered_response.size < @query.effective_size
          end

          # Then we try again, excluding the id sets which have already gotten complete results.
          another_attempt_results = fetch_via_single_query_with_merged_filters(
            id_sets_with_apparently_incomplete_results,
            remaining_attempts: remaining_attempts - 1
          ) { yield }

          # Finally, we merge the results.
          filtered_responses_by_id_set.merge(another_attempt_results)
        end

        def fetch_via_separate_queries(id_sets, requested_fields: [])
          queries = id_sets.map do |ids|
            @query.merge_with(filters: filters_for(ids), requested_fields: requested_fields)
          end

          results = QuerySource.execute_many(queries, for_context: @context)
          queries.map { |q| results.fetch(q) }
        end

        def filters_for(ids)
          join_filter = build_filter(@join.filter_id_field_name, nil, @join.foreign_key_nested_paths, ids.to_a)

          if @join.additional_filter.empty?
            [join_filter]
          else
            [join_filter, @join.additional_filter]
          end
        end

        def build_filter(path, previous_nested_path, nested_paths, ids)
          next_nested_path, *rest_nested_paths = nested_paths

          if next_nested_path.nil?
            path = path.delete_prefix("#{previous_nested_path}.") if previous_nested_path
            {path => {@schema_element_names.equal_to_any_of => ids}}
          else
            sub_filter = build_filter(path, next_nested_path, rest_nested_paths, ids)
            next_nested_path = next_nested_path.delete_prefix("#{previous_nested_path}.") if previous_nested_path
            {next_nested_path => {@schema_element_names.any_satisfy => sub_filter}}
          end
        end

        def time_duration
          start_time = @monotonic_clock.now_in_ms
          result = yield
          stop_time = @monotonic_clock.now_in_ms
          [stop_time - start_time, result]
        end

        # Converts the given list of responses into a format we can safely log when we are logging
        # response differences. We include the `id` (to identify the document) and the `hash` (so
        # we can tell if the payload of a document differed, without logging the contents of that
        # payload).
        def loggable_results(responses)
          responses.map do |response|
            response.documents.map do |doc|
              "#{doc.id} (hash: #{doc.hash})"
            end
          end
        end
      end
    end
  end
end
