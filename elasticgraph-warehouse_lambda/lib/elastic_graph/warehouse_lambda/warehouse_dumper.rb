# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/datastore_indexing_router"
require "elastic_graph/indexer/operation/result"
require "json"
require "time"
require "securerandom"
require "zlib"

module ElasticGraph
  class WarehouseLambda
    # Responsible for dumping data into the data warehouse. Implements the same interface as `DatastoreIndexingRouter` from
    # `elasticgraph-indexer` so that it can be used in place of the standard datastore indexing router.
    class WarehouseDumper
      # @return [String] message type for logging when a batch is received
      LOG_MSG_RECEIVED_BATCH = "WarehouseLambdaReceivedBatch"

      # @return [String] message type for logging when a file is dumped to S3
      LOG_MSG_DUMPED_FILE = "DumpedToWarehouseFile"

      def initialize(logger:, s3_client:, s3_bucket_name:, s3_file_prefix:, latest_json_schema_version:, clock:)
        @logger = logger
        @s3_client = s3_client
        @s3_bucket_name = s3_bucket_name
        @s3_file_prefix = s3_file_prefix
        @latest_json_schema_version = latest_json_schema_version
        @clock = clock
      end

      # Processes a batch of indexing operations by dumping them to S3 as gzipped JSONL files.
      # Operations are grouped by GraphQL type, with each type written to a separate file.
      #
      # @param operations [Array<Operation>] the indexing operations to process
      # @param refresh [Boolean] ignored (included for interface compatibility with DatastoreIndexingRouter)
      # @return [BulkResult] result containing success status for all operations
      def bulk(operations, refresh: false)
        operations_by_type = operations.group_by { |op| op.event.fetch("type") }

        @logger.info({
          "message_type" => LOG_MSG_RECEIVED_BATCH,
          "record_counts_by_type" => operations_by_type.transform_values(&:size)
        })

        operations_by_type.each do |type, operations|
          # Operations coming from the indexer are always Update operations for warehouse dumping
          update_operations = operations #: ::Array[::ElasticGraph::Indexer::Operation::Update]
          jsonl_data = build_jsonl_file_from(update_operations)

          # Skip S3 upload if all operations were filtered out (no data to write)
          next if jsonl_data.empty?

          gzip_data = compress(jsonl_data)
          s3_key = generate_s3_key_for(type)

          # Use if_none_match: "*" to prevent overwrites (defense-in-depth, though UUIDs make collisions impossible)
          @s3_client.put_object(
            bucket: @s3_bucket_name,
            key: s3_key,
            body: gzip_data,
            checksum_algorithm: :sha256,
            if_none_match: "*"
          )

          @logger.info({
            "message_type" => LOG_MSG_DUMPED_FILE,
            "s3_bucket" => @s3_bucket_name,
            "s3_key" => s3_key,
            "type" => type,
            "record_count" => operations.size,
            "json_size" => jsonl_data.bytesize,
            "gzip_size" => gzip_data.bytesize
          })
        end

        ops_and_results = operations.map do |op|
          [op, ::ElasticGraph::Indexer::Operation::Result.success_of(op)]
        end #: ::Array[[::ElasticGraph::Indexer::_Operation, ::ElasticGraph::Indexer::Operation::Result]]

        ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult.new({"warehouse" => ops_and_results})
      end

      # Returns existing event versions for the given operations.
      # Always returns an empty hash since the warehouse doesn't maintain version state.
      #
      # @param operations [Array<Operation>] the operations to check (unused)
      # @return [Hash] empty hash (warehouse doesn't track versions)
      def source_event_versions_in_index(operations)
        {}
      end

      private

      def generate_s3_key_for(type)
        date = @clock.now.utc.strftime("%Y-%m-%d")
        uuid = ::SecureRandom.uuid

        [
          @s3_file_prefix,
          type,
          "v#{@latest_json_schema_version}",
          date,
          "#{uuid}.jsonl.gz"
        ].join("/")
      end

      def build_jsonl_file_from(operations)
        operation_payloads = operations.filter_map do |op|
          # Only include operations where the update target matches the event type (excludes derived indices)
          next nil if op.update_target.type != op.event.fetch("type")
          # Skip operations with no datastore payload (e.g., delete operations or invalid data)
          next nil if op.to_datastore_bulk.empty?

          payload_body = op.to_datastore_bulk[1]
          script = payload_body.fetch(:script)
          params = script.fetch(:params)
          data = params.fetch("data").merge({
            "id" => params.fetch("id"),
            "__eg_version" => params.fetch("version")
          })

          ::JSON.generate(data)
        end

        operation_payloads.join("\n")
      end

      def compress(jsonl_data)
        io = ::StringIO.new
        gz = ::Zlib::GzipWriter.new(io, ::Zlib::DEFAULT_COMPRESSION, ::Zlib::DEFAULT_STRATEGY)

        begin
          gz << jsonl_data
        ensure
          gz.close
        end
        io.string
      end
    end
  end
end
