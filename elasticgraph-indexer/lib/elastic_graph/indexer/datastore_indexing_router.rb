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
          unsupported_event_ids = unsupported_ops.flat_map do |op|
            op.all_events.map { |event| Indexer::EventID.from_event(event).to_s }
          end.uniq

          raise IndexingFailuresError,
            "The index definitions for #{unsupported_ops.size} operations " \
            "(#{unsupported_event_ids.join(", ")}) " \
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
          # @type block: [::String, ::Symbol, ::Array[untyped] | ::Hash[_Operation, ::Array[::Integer]]]

          ops, unversioned_ops = all_ops.partition(&:versioned?) # : [::Array[Operation::Update], ::Array[Operation::Update]]

          msearch_response =
            if (client = @datastore_clients_by_name[client_name]) && ops.any?
              body = ops.flat_map do |op|
                [
                  # Note: we intentionally search the entire index expression, not just an individual index based on a rollover timestamp.
                  # And we intentionally do NOT provide a routing value--we want to find the version, no matter what shard the document
                  # lives on.
                  #
                  # Since this `source_event_versions_in_index` is for handling malformed events, its possible that the
                  # rollover timestamp or routing value on the operation is wrong and that the correct document lives in
                  # a different shard and index than what the operation is targeted at. We want to search across all of them
                  # so that we will find it, regardless of where it lives.
                  {index: op.destination_index_def.index_expression_for_search},
                  {
                    # Filter to the documents matching the id.
                    query: {ids: {values: [op.doc_id]}},
                    # We only care about the version.
                    _source: {includes: ["__versions.#{op.update_target.relationship}"]}
                  }
                ]
              end

              client.msearch(body: body)
            else
              # The named client doesn't exist, so we don't have any versions for the docs.
              {"responses" => ops.map { |op| {"hits" => {"hits" => _ = []}} }}
            end

          errors = msearch_response.fetch("responses").select { |res| res["error"] }

          if errors.empty?
            # We assume the size of the ops and the other array is the same and it cannot have `nil`.
            zip = ops.zip(msearch_response.fetch("responses")) # : ::Array[[Operation::Update, ::Hash[::String, ::Hash[::String, untyped]]]]

            versions_by_op = zip.to_h do |(op, response)|
              hits = response.fetch("hits").fetch("hits")

              if hits.size > 1
                # Got multiple results. The document is duplicated in multiple shards or indexes. Log a warning about this.
                @logger.warn({
                  "message_type" => "IdentifyDocumentVersionsGotMultipleResults",
                  "index" => hits.map { |h| h["_index"] },
                  "routing" => hits.map { |h| h["_routing"] },
                  "id" => hits.map { |h| h["_id"] },
                  "version" => hits.map { |h| h["_version"] }
                })
              end

              versions = hits.filter_map do |hit|
                hit.dig("_source", "__versions", op.update_target.relationship, hit.fetch("_id"))
              end

              [op, versions.uniq]
            end

            unversioned_ops_hash = unversioned_ops.to_h do |op|
              [op, []] # : [Operation::Update, ::Array[::Integer]]
            end

            [client_name, :success, versions_by_op.merge(unversioned_ops_hash)]
          else
            [client_name, :failure, errors]
          end
        end

        failures = client_names_and_results.flat_map do |(client_name, success_or_failure, results)|
          if success_or_failure == :success
            []
          else
            results.map do |result|
              "From cluster #{client_name}: #{::JSON.generate(result, space: " ")}"
            end
          end
        end

        if failures.empty?
          # All results are success and the third element of the tuple is a hash.
          # Assign the results to narrow down the type.
          success_results = client_names_and_results # : ::Array[[::String, ::Symbol, ::Hash[_Operation, ::Array[::Integer]]]]

          success_results.each_with_object(_ = {}) do |(client_name, _success_or_failure, results), accum|
            results.each do |op, version|
              (accum[op] ||= {})[client_name] = version
            end
          end
        else
          raise Errors::IdentifyDocumentVersionsFailedError, "Got #{failures.size} failure(s) while querying the datastore " \
            "for document versions:\n\n#{failures.join("\n")}"
        end
      end
    end
  end
end
