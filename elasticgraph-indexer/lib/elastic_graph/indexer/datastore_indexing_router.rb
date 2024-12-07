# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/datastore_core/index_config_normalizer"
require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/hash_differ"
require "elastic_graph/indexer/indexing_failures_error"
require "elastic_graph/support/threading"

module ElasticGraph
  class Indexer
    # Responsible for routing datastore indexing requests to the appropriate cluster and index.
    class DatastoreIndexingRouter
      # In this class, we internally cache the datastore mapping for an index definition, so that we don't have to
      # fetch the mapping from the datastore on each call to `bulk`. It rarely changes and ElasticGraph is designed so that
      # mapping updates are applied before deploying the indexer with a new mapping.
      #
      # However, if an engineer forgets to apply a mapping update before deploying, they'll run into "mappings are incomplete"
      # errors. They can updated the mapping to fix it, but the use of caching in this class could mean that the fix doesn't
      # necessarily work right away. The app would have to be deployed or restarted so that the caches are cleared. That could
      # be annoying.
      #
      # To address this issue, we're adding an expiration on the caching of the index mappings. Re-fetching the index
      # mapping once every few minutes is no big deal and will allow the indexer to recover on its own after a mapping
      # update has been applied without requiring a deploy or a restart.
      #
      # The expiration is a range so that, when we have many processes running, and they all started around the same time,
      # (say, after a deploy!), they don't all expire their caches in sync, leading to spiky load on the datastore. Instead,
      # the random distribution of expiration times will spread out the load.
      MAPPING_CACHE_MAX_AGE_IN_MS_RANGE = (5 * 60 * 1000)..(10 * 60 * 1000)

      def initialize(
        datastore_clients_by_name:,
        mappings_by_index_def_name:,
        monotonic_clock:,
        logger:
      )
        @datastore_clients_by_name = datastore_clients_by_name
        @logger = logger
        @monotonic_clock = monotonic_clock
        @cached_mappings = {}

        @mappings_by_index_def_name = mappings_by_index_def_name.transform_values do |mappings|
          DatastoreCore::IndexConfigNormalizer.normalize_mappings(mappings)
        end
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
      #
      # Note: before any operations are attempted, the datastore indices are validated for consistency
      # with the mappings we expect, meaning that no bulk operations will be attempted if that is not up-to-date.
      def bulk(operations, refresh: false)
        # Before writing these operations, verify their destination index mapping are consistent.
        validate_mapping_completeness_of!(:accessible_cluster_names_to_index_into, *operations.map(&:destination_index_def).uniq)

        ops_by_client = ::Hash.new { |h, k| h[k] = [] } # : ::Hash[DatastoreCore::_Client, ::Array[_Operation]]
        unsupported_ops = ::Set.new # : ::Set[_Operation]

        operations.reject { |op| op.to_datastore_bulk.empty? }.each do |op|
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
        ops_by_client_name = operations.each_with_object(::Hash.new { |h, k| h[k] = [] }) do |op, ops_hash|
          # Note: this intentionally does not use `accessible_cluster_names_to_index_into`.
          # We want to fail with clear error if any clusters are inaccessible instead of silently ignoring
          # the named cluster. The `IndexingFailuresError` provides a clear error.
          cluster_names = op.destination_index_def.clusters_to_index_into
          cluster_names.each { |cluster_name| ops_hash[cluster_name] << op }
        end

        client_names_and_results = Support::Threading.parallel_map(ops_by_client_name) do |(client_name, all_ops)|
          ops, unversioned_ops = all_ops.partition(&:versioned?)

          msearch_response =
            if (client = @datastore_clients_by_name[client_name]) && ops.any?
              body = ops.flat_map do |op|
                # We only care about the source versions, but the way we get it varies.
                include_version =
                  if op.destination_index_def.use_updates_for_indexing?
                    {_source: {includes: [
                      "__versions.#{op.update_target.relationship}",
                      # The update_data script before ElasticGraph v0.8 used __sourceVersions[type] instead of __versions[relationship].
                      # To be backwards-compatible we need to fetch the data at both paths.
                      #
                      # TODO: Drop this when we no longer need to maintain backwards-compatibility.
                      "__sourceVersions.#{op.event.fetch("type")}"
                    ]}}
                  else
                    {version: true, _source: false}
                  end

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
                  # Filter to the documents matching the id.
                  {query: {ids: {values: [op.doc_id]}}}.merge(include_version)
                ]
              end

              client.msearch(body: body)
            else
              # The named client doesn't exist, so we don't have any versions for the docs.
              {"responses" => ops.map { |op| {"hits" => {"hits" => _ = []}} }}
            end

          errors = msearch_response.fetch("responses").select { |res| res["error"] }

          if errors.empty?
            versions_by_op = ops.zip(msearch_response.fetch("responses")).to_h do |(op, response)|
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

              if op.destination_index_def.use_updates_for_indexing?
                versions = hits.filter_map do |hit|
                  hit.dig("_source", "__versions", op.update_target.relationship, hit.fetch("_id")) ||
                    # The update_data script before ElasticGraph v0.8 used __sourceVersions[type] instead of __versions[relationship].
                    # To be backwards-compatible we need to fetch the data at both paths.
                    #
                    # TODO: Drop this when we no longer need to maintain backwards-compatibility.
                    hit.dig("_source", "__sourceVersions", op.event.fetch("type"), hit.fetch("_id"))
                end

                [op, versions.uniq]
              else
                [op, hits.map { |h| h.fetch("_version") }.uniq]
              end
            end

            unversioned_ops_hash = unversioned_ops.to_h do |op|
              [op, []] # : [_Operation, ::Array[::Integer]]
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
          client_names_and_results.each_with_object(_ = {}) do |(client_name, _success_or_failure, results), accum|
            results.each do |op, version|
              (accum[op] ||= {})[client_name] = version
            end
          end
        else
          raise Errors::IdentifyDocumentVersionsFailedError, "Got #{failures.size} failure(s) while querying the datastore " \
            "for document versions:\n\n#{failures.join("\n")}"
        end
      end

      # Queries the datastore mapping(s) for the given index definition(s) to verify that they are up-to-date
      # with our schema artifacts, raising an error if the datastore mappings are missing fields that we
      # expect. (Extra fields are allowed, though--we'll just ignore them).
      #
      # This is intended for use when you want a strong guarantee before proceeding that the indices are current,
      # such as before indexing data, or after applying index updates (to "prove" that everything is how it should
      # be).
      #
      # This correctly queries the datastore clusters specified via `index_into_clusters` in config,
      # but ignores clusters specified via `query_cluster` (since this isn't intended to be used as part
      # of the query flow).
      #
      # For a rollover template, this takes care of verifying the template itself and also any indices that originated
      # from the template.
      #
      # Note also that this caches the datastore mappings, since this is intended to be used to verify an index
      # before we index data into it, and we do not want to impose a huge performance penalty on that process (requiring
      # multiple datastore requests before we index each document...). In general, the index mapping only changes
      # when we make it change, and we deploy and restart ElasticGraph after any index mapping changes, so we do not
      # need to worry about it mutating during the lifetime of a single process (particularly given the expense of doing
      # so).
      def validate_mapping_completeness_of!(index_cluster_name_method, *index_definitions)
        diffs_by_cluster_and_index_name = index_definitions.reduce(_ = {}) do |accum, index_def|
          accum.merge(mapping_diffs_for(index_def, index_cluster_name_method))
        end

        if diffs_by_cluster_and_index_name.any?
          formatted_diffs = diffs_by_cluster_and_index_name.map do |(cluster_name, index_name), diff|
            <<~EOS
              On cluster `#{cluster_name}` and index/template `#{index_name}`:
              #{diff}
            EOS
          end.join("\n\n")

          raise Errors::ConfigError, "Datastore index mappings are incomplete compared to the current schema. " \
            "The diff below uses the datastore index mapping as the base, and shows the expected mapping as a diff. " \
            "\n\n#{formatted_diffs}"
        end
      end

      private

      def mapping_diffs_for(index_definition, index_cluster_name_method)
        expected_mapping = @mappings_by_index_def_name.fetch(index_definition.name)

        index_definition.public_send(index_cluster_name_method).flat_map do |cluster_name|
          datastore_client = datastore_client_named(cluster_name)

          cached_mappings_for(index_definition, datastore_client).filter_map do |index, mapping_in_index|
            if (diff = HashDiffer.diff(mapping_in_index, expected_mapping, ignore_ops: [:-]))
              [[cluster_name, index.name], diff]
            end
          end
        end.to_h
      end

      def cached_mappings_for(index_definition, datastore_client)
        key = [datastore_client, index_definition] # : [DatastoreCore::_Client, DatastoreCore::indexDefinition]
        cached_mapping = @cached_mappings[key] ||= new_cached_mapping(fetch_mappings_from_datastore(index_definition, datastore_client))

        return cached_mapping.mappings if @monotonic_clock.now_in_ms < cached_mapping.expires_at

        begin
          fetch_mappings_from_datastore(index_definition, datastore_client).tap do |mappings|
            @logger.info "Mapping cache expired for #{index_definition.name}; cleared it from the cache and re-fetched the mapping."
            @cached_mappings[key] = new_cached_mapping(mappings)
          end
        rescue => e
          @logger.warn <<~EOS
            Mapping cache expired for #{index_definition.name}; attempted to re-fetch it but got an error[1]. Will continue using expired mapping information for now.

            [1] #{e.class}: #{e.message}
            #{e.backtrace.join("\n")}
          EOS

          # Update the cached mapping so that the expiration is reset.
          @cached_mappings[key] = new_cached_mapping(cached_mapping.mappings)

          cached_mapping.mappings
        end
      end

      def fetch_mappings_from_datastore(index_definition, datastore_client)
        # We need to also check any related indices...
        indices_to_check = [index_definition] + index_definition.related_rollover_indices(datastore_client)

        indices_to_check.to_h do |index|
          [index, index.mappings_in_datastore(datastore_client)]
        end
      end

      def new_cached_mapping(mappings)
        CachedMapping.new(mappings, @monotonic_clock.now_in_ms + rand(MAPPING_CACHE_MAX_AGE_IN_MS_RANGE).to_i)
      end

      def datastore_client_named(name)
        @datastore_clients_by_name.fetch(name)
      end

      CachedMapping = ::Data.define(:mappings, :expires_at)
    end
  end
end
