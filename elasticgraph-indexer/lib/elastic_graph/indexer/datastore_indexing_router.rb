# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/indexing_failures_error"
require "elastic_graph/support/threading"

module ElasticGraph
  class Indexer
    # Responsible for routing datastore indexing requests to the appropriate cluster and index.
    class DatastoreIndexingRouter
      def initialize(
        datastore_clients_by_name:,
        logger:
      )
        @datastore_clients_by_name = datastore_clients_by_name
        @logger = logger
      end

      # Proxies `client#bulk` by converting `operations` to their bulk
      # form. Returns a hash between a cluster and a list of successfully applied operations on that cluster.
      #
      # For each operation, 1 of 4 things will happen, each of which will be treated differently:
      #
      #   1. The operation was successfully applied to the datastore and updated its state.
      #      The operation will be included in the successful operation of the returned result.
      #   2. The operation could not even be attempted. For example, an `Update` operation
      #      cannot be attempted when the source event has `nil` for the field used as the source of
      #      the destination type's id. The returned result will not include this operation.
      #   3. The operation was a no-op due to the external version not increasing. This happens when we
      #      process a duplicate or out-of-order event. The operation will be included in the returned
      #      result's list of noop results.
      #   4. The operation failed outright for some other reason. The operation will be included in the
      #      returned result's failure results.
      #
      # It is the caller's responsibility to deal with any returned failures as this method does not
      # raise an exception in that case.
      def bulk(operations, refresh: false)
        ops_by_client = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[DatastoreCore::_Client, ::Array[_Operation]]
        unsupported_ops = ::Set.new # : ::Set[_Operation]

        operations.each do |op|
          # Note: this intentionally does not use `accessible_cluster_names_to_index_into`.
          # We want to fail with clear error if any clusters are inaccessible instead of silently ignoring
          # the named cluster. The `IndexingFailuresError` provides a clear error.
          cluster_names = op.destination_index_def.clusters_to_index_into

          cluster_names.each do |cluster_name|
            if (client = @datastore_clients_by_name[cluster_name])
              ops = ops_by_client[client] # : ::Array[::ElasticGraph::Indexer::_Operation]
              ops << op
            else
              unsupported_ops << op
            end
          end

          unsupported_ops << op if cluster_names.empty?
        end

        unless unsupported_ops.empty?
          raise IndexingFailuresError,
            "The index definitions for #{unsupported_ops.size} operations " \
            "(#{unsupported_ops.map { |o| Indexer::EventID.from_event(o.event) }.join(", ")}) " \
            "were configured to be inaccessible. Check the configuration, or avoid sending " \
            "events of this type to this ElasticGraph indexer."
        end

        ops_and_results_by_cluster = Support::Threading.parallel_map(ops_by_client) do |(client, ops)|
          responses = client.bulk(body: ops.flat_map(&:to_datastore_bulk), refresh: refresh).fetch("items")

          # As per https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html#bulk-api-response-body,
          # > `items` contains the result of each operation in the bulk request, in the order they were submitted.
          # Thus, we can trust it has the same cardinality as `ops` and they can be zipped together.
          ops_and_results = ops.zip(responses).map { |(op, response)| [op, op.categorize(response)] }
          [client.cluster_name, ops_and_results]
        end.to_h

        BulkResult.new(ops_and_results_by_cluster)
      end

      # Return type encapsulating all of the results of the bulk call.
      class BulkResult < ::Data.define(:ops_and_results_by_cluster, :noop_results, :failure_results)
        def initialize(ops_and_results_by_cluster:)
          results_by_category = ops_and_results_by_cluster.values
            .flat_map { |ops_and_results| ops_and_results.map(&:last) }
            .group_by(&:category)

          super(
            ops_and_results_by_cluster: ops_and_results_by_cluster,
            noop_results: results_by_category[:noop] || [],
            failure_results: results_by_category[:failure] || []
          )
        end

        # Returns successful operations grouped by the cluster they were applied to. If there are any
        # failures, raises an exception to alert the caller to them unless `check_failures: false` is passed.
        #
        # This is designed to prevent failures from silently being ignored. For example, in tests
        # we often call `successful_operations` or `successful_operations_by_cluster_name` and don't
        # bother checking `failure_results` (because we don't expect a failure). If there was a failure
        # we want to be notified about it.
        def successful_operations_by_cluster_name(check_failures: true)
          if check_failures && failure_results.any?
            raise IndexingFailuresError, "Got #{failure_results.size} indexing failure(s):\n\n" \
              "#{failure_results.map.with_index(1) { |result, idx| "#{idx}. #{result.summary}" }.join("\n\n")}"
          end

          ops_and_results_by_cluster.transform_values do |ops_and_results|
            ops_and_results.filter_map do |(op, result)|
              op if result.category == :success
            end
          end
        end

        # Returns a flat list of successful operations. If there are any failures, raises an exception
        # to alert the caller to them unless `check_failures: false` is passed.
        #
        # This is designed to prevent failures from silently being ignored. For example, in tests
        # we often call `successful_operations` or `successful_operations_by_cluster_name` and don't
        # bother checking `failure_results` (because we don't expect a failure). If there was a failure
        # we want to be notified about it.
        def successful_operations(check_failures: true)
          successful_operations_by_cluster_name(check_failures: check_failures).values.flatten(1).uniq
        end
      end

      # Given a list of operations (which can contain different types of operations!), queries the datastore
      # to identify the source event versions stored on the corresponding documents.
      #
      # This was specifically designed to support dealing with malformed events. If an event is malformed we
      # usually want to raise an exception, but if the document targeted by the malformed event is at a newer
      # version in the index than the version number in the event, the malformed state of the event has
      # already been superseded by a corrected event and we can just log a message instead. This method specifically
      # supports that logic.
      #
      # The lookup runs in two stages:
      #
      #  1. Narrow stage. Operations are grouped by `(target_index, routing, relationship)` reusing the
      #     same index name and routing value computation the primary bulk write uses. One `search`
      #     per group is issued, combining all doc_ids in that group into a single `ids` query. When
      #     routing is set this typically targets a single shard of a single yearly index.
      #  2. Wildcard fallback stage. Operations that the narrow stage did not resolve (no hits for
      #     their doc_id) fall back to the original behavior: a search across the full rollover
      #     index expression with no routing. This preserves the framework's guarantee that a
      #     malformed event whose doc lives at a different (index, shard) than its rollover/routing
      #     fields imply can still be identified as superseded.
      #
      # For well-formed failure batches this reduces the shard-level fan-out from
      # `N_failures * shards_per_index * indices_in_expression` (which for 12 yearly rollover
      # indices at 1024 shards each is ~8,400 shard tasks per failure) to approximately 1 shard
      # task per group. Malformed events pay one additional wildcard round-trip, which matches
      # today's cost.
      #
      # If the datastore returns errors for any of the calls, this method will raise an exception.
      # Otherwise, this method returns a nested hash:
      #
      #  - The outer hash maps operations to an inner hash of results for that operation.
      #  - The inner hash maps datastore cluster/client names to the version number for that operation from the datastore cluster.
      #
      # Note that the returned `version` for an operation on a cluster can be `nil` (as when the document is not found,
      # or for an operation type that doesn't store source versions).
      #
      # This nested structure is necessary because a single operation can target more than one datastore
      # cluster, and a document may have different source event versions in different datastore clusters.
      def source_event_versions_in_index(operations)
        ops_by_client_name = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[::String, ::Array[_Operation]]
        operations.each do |op|
          # Note: this intentionally does not use `accessible_cluster_names_to_index_into`.
          # We want to fail with clear error if any clusters are inaccessible instead of silently ignoring
          # the named cluster. The `IndexingFailuresError` provides a clear error.
          cluster_names = op.destination_index_def.clusters_to_index_into
          cluster_names.each { |cluster_name| ops_by_client_name[cluster_name] << op }
        end

        client_names_and_results = Support::Threading.parallel_map(ops_by_client_name) do |(client_name, all_ops)|
          versioned_ops, unversioned_ops = all_ops.partition(&:versioned?)

          versions_by_op =
            if (client = @datastore_clients_by_name[client_name]) && versioned_ops.any?
              narrow_result = narrow_version_lookup(client, versioned_ops)
              missing_ops = versioned_ops.reject { |op| narrow_result.fetch(op, []).any? }
              wide_result = missing_ops.any? ? wide_version_lookup(client, missing_ops) : {}
              narrow_result.merge(wide_result)
            else
              # The named client doesn't exist, so we don't have any versions for the docs.
              versioned_ops.to_h { |op| [op, []] }
            end

          unversioned_ops.each { |op| versions_by_op[op] = [] }
          [client_name, versions_by_op]
        end

        client_names_and_results.each_with_object(_ = {}) do |(client_name, versions_by_op), accum|
          versions_by_op.each do |op, versions|
            (accum[op] ||= {})[client_name] = versions
          end
        end
      end

      private

      # Stage 1 of {#source_event_versions_in_index}: groups operations by (target_index, routing,
      # relationship) and issues a single `msearch` where each sub-query is a group, combining all
      # doc_ids for that group into a single `ids` query targeting the specific yearly index and
      # shard implied by the operation's rollover/routing fields. Returns a hash of operation to
      # versions, with an empty array for operations whose doc_id was not found.
      def narrow_version_lookup(client, ops)
        groups = ops.group_by { |op| narrow_lookup_key_for(op) }.to_a

        body = groups.flat_map do |((target_index, routing, relationship), group_ops)|
          header = {index: target_index}
          header[:routing] = routing if routing && !routing.to_s.empty?
          [
            header,
            {
              query: {ids: {values: group_ops.map(&:doc_id)}},
              _source: {includes: ["__versions.#{relationship}"]},
              size: group_ops.size
            }
          ]
        end

        msearch_response = client.msearch(body: body)
        errors = msearch_response.fetch("responses").select { |res| res["error"] }

        unless errors.empty?
          detail = errors.map { |e| ::JSON.generate(e, space: " ") }.join("\n")
          raise Errors::IdentifyDocumentVersionsFailedError,
            "Got #{errors.size} failure(s) during narrow version lookup:\n\n#{detail}"
        end

        group_responses = groups.zip(msearch_response.fetch("responses"))

        group_responses.each_with_object({}) do |((_key, group_ops), response), accum|
          hits_by_id = response.fetch("hits").fetch("hits").group_by { |h| h.fetch("_id") }

          group_ops.each do |op|
            hits = hits_by_id[op.doc_id] || []
            log_multiple_hits_warning(hits) if hits.size > 1
            accum[op] = extract_versions(hits, op)
          end
        end
      end

      # Stage 2 of {#source_event_versions_in_index}: wildcard lookup with no routing, used for
      # operations that stage 1 did not resolve. Matches the framework's original supersede-check
      # behavior so malformed events (with wrong rollover timestamp or routing) can still be
      # identified.
      def wide_version_lookup(client, ops)
        body = ops.flat_map do |op|
          [
            {index: op.destination_index_def.index_expression_for_search},
            {
              query: {ids: {values: [op.doc_id]}},
              _source: {includes: ["__versions.#{op.update_target.relationship}"]}
            }
          ]
        end

        msearch_response = client.msearch(body: body)
        errors = msearch_response.fetch("responses").select { |res| res["error"] }

        unless errors.empty?
          detail = errors.map { |e| ::JSON.generate(e, space: " ") }.join("\n")
          raise Errors::IdentifyDocumentVersionsFailedError,
            "Got #{errors.size} failure(s) during wildcard version lookup:\n\n#{detail}"
        end

        ops.zip(msearch_response.fetch("responses")).to_h do |(op, response)|
          hits = response.fetch("hits").fetch("hits")
          log_multiple_hits_warning(hits) if hits.size > 1
          [op, extract_versions(hits, op)]
        end
      end

      def narrow_lookup_key_for(op)
        target_index = op.destination_index_def.index_name_for_writes(
          op.prepared_record,
          timestamp_field_path: op.update_target.rollover_timestamp_value_source
        )
        routing = op.destination_index_def.routing_value_for_prepared_record(
          op.prepared_record,
          route_with_path: op.update_target.routing_value_source,
          id_path: op.update_target.id_source
        )
        [target_index, routing, op.update_target.relationship]
      end

      def extract_versions(hits, op)
        versions = hits.filter_map do |hit|
          hit.dig("_source", "__versions", op.update_target.relationship, hit.fetch("_id"))
        end
        versions.uniq
      end

      def log_multiple_hits_warning(hits)
        @logger.warn({
          "message_type" => "IdentifyDocumentVersionsGotMultipleResults",
          "index" => hits.map { |h| h["_index"] },
          "routing" => hits.map { |h| h["_routing"] },
          "id" => hits.map { |h| h["_id"] },
          "version" => hits.map { |h| h["_version"] }
        })
      end

      public
    end
  end
end
