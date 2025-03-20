# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/indexer/event_id"
require "elastic_graph/indexer/indexing_failures_error"
require "time"

module ElasticGraph
  class Indexer
    class Processor
      def initialize(
        datastore_router:,
        operation_factory:,
        logger:,
        indexing_latency_slo_thresholds_by_timestamp_in_ms:,
        clock: ::Time
      )
        @datastore_router = datastore_router
        @operation_factory = operation_factory
        @clock = clock
        @logger = logger
        @indexing_latency_slo_thresholds_by_timestamp_in_ms = indexing_latency_slo_thresholds_by_timestamp_in_ms
      end

      # Processes the given events, writing them to the datastore. If any events are invalid, an
      # exception will be raised indicating why the events were invalid, but the valid events will
      # still be written to the datastore. No attempt is made to provide atomic "all or nothing"
      # behavior.
      def process(events, refresh_indices: false)
        failures = process_returning_failures(events, refresh_indices: refresh_indices)
        return if failures.empty?
        raise IndexingFailuresError.for(failures: failures, events: events)
      end

      # Like `process`, but returns failures instead of raising an exception.
      # The caller is responsible for handling the failures.
      def process_returning_failures(events, refresh_indices: false)
        factory_results_by_event = events.to_h { |event| [event, @operation_factory.build(event)] }

        factory_results = factory_results_by_event.values

        bulk_result = @datastore_router.bulk(factory_results.flat_map(&:operations), refresh: refresh_indices)
        successful_operations = bulk_result.successful_operations(check_failures: false)

        calculate_latency_metrics(successful_operations, bulk_result.noop_results)

        all_failures =
          factory_results.map(&:failed_event_error).compact +
          bulk_result.failure_results.map do |result|
            all_operations_for_event = factory_results_by_event.fetch(result.event).operations
            FailedEventError.from_failed_operation_result(result, all_operations_for_event.to_set)
          end

        categorize_failures(all_failures, events)
      end

      private

      def categorize_failures(failures, events)
        source_event_versions_by_cluster_by_op = @datastore_router.source_event_versions_in_index(
          failures.flat_map { |f| f.versioned_operations.to_a }
        )

        superseded_failures, outstanding_failures = failures.partition do |failure|
          failure.versioned_operations.size > 0 && failure.versioned_operations.all? do |op|
            # Under normal conditions, we expect to get back only one version per operation per cluster.
            # However, when a field used for routing or index rollover has mutated, we can wind up with
            # multiple copies of the document in different indexes or shards. `source_event_versions_in_index`
            # returns a list of found versions.
            #
            # We only need to consider the largest version when deciding if a failure has been supeseded or not.
            # An event with a larger version is considered to be a full replacement for an earlier event for the
            # same entity, so if we've processed an event for the same entity with a larger version, we can consider
            # the failure superseded.
            max_version_per_cluster = source_event_versions_by_cluster_by_op.fetch(op).values.map(&:max)

            # We only consider an event to be superseded if the document version in the datastore
            # for all its versioned operations is greater than the version of the failing event.
            max_version_per_cluster.all? { |v| v && v > failure.version }
          end
        end

        if superseded_failures.any?
          superseded_ids = superseded_failures.map { |f| EventID.from_event(f.event).to_s }
          @logger.warn(
            "Ignoring #{superseded_ids.size} malformed event(s) because they have been superseded " \
            "by corrected events targeting the same id: #{superseded_ids.join(", ")}."
          )
        end

        outstanding_failures
      end

      def calculate_latency_metrics(successful_operations, noop_results)
        current_time = @clock.now
        successful_events = successful_operations.map(&:event).to_set
        noop_events = noop_results.map(&:event).to_set
        all_operations_events = successful_events + noop_events

        all_operations_events.each do |event|
          latencies_in_ms_from = {} # : Hash[String, Integer]
          slo_results = {} # : Hash[String, String]

          latency_timestamps = event.fetch("latency_timestamps", _ = {})
          latency_timestamps.each do |ts_name, ts_value|
            metric_value = ((current_time - Time.iso8601(ts_value)) * 1000).round

            latencies_in_ms_from[ts_name] = metric_value

            if (threshold = @indexing_latency_slo_thresholds_by_timestamp_in_ms[ts_name])
              slo_results[ts_name] = (metric_value >= threshold) ? "bad" : "good"
            end
          end

          result = successful_events.include?(event) ? "success" : "noop"

          @logger.info({
            "message_type" => "ElasticGraphIndexingLatencies",
            "message_id" => event["message_id"],
            "event_type" => event.fetch("type"),
            "event_id" => EventID.from_event(event).to_s,
            JSON_SCHEMA_VERSION_KEY => event.fetch(JSON_SCHEMA_VERSION_KEY),
            "latencies_in_ms_from" => latencies_in_ms_from,
            "slo_results" => slo_results,
            "result" => result
          })
        end
      end
    end
  end
end
