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
      # `elasticgraph-indexer` so that it can be used in place of the standard datastore indexing router:
      #
      # https://github.com/squareup/elasticgraph-public/blob/v0.18.0.5/elasticgraph-indexer/lib/elastic_graph/indexer/datastore_indexing_router.rb#L76
      class WarehouseDumper
        def initialize(logger:, s3_client:, s3_bucket_name:, s3_file_prefix:, latest_json_schema_version:, clock:)
          @logger = logger
          @s3_client = s3_client
          @s3_bucket_name = s3_bucket_name
          @s3_file_prefix = s3_file_prefix
          @latest_json_schema_version = latest_json_schema_version
          @clock = clock
        end

        def bulk(operations, refresh: false)
          operations_by_type = operations.group_by { |op| op.event.fetch("type") }

          @logger.info({
            "message_type" => "WarehouseLambdaReceivedBatch",
            "record_counts_by_type" => operations_by_type.transform_values(&:size)
          })

          operations_by_type.each do |type, operations|
            jsonl_data = build_jsonl_file_from(operations)
            gzip_data = compress(jsonl_data)
            s3_key = generate_s3_key_for(type)

            @s3_client.put_object(
              bucket: @s3_bucket_name,
              key: s3_key,
              body: gzip_data,
              checksum_algorithm: :sha256,
              if_none_match: "*"
            )

            @logger.info({
              "message_type" => "DumpedToWarehouseFile",
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
          end

          ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult.new({"warehouse" => ops_and_results})
        end

        def source_event_versions_in_index(operations)
          {}
        end

        private

        def generate_s3_key_for(type)
          date, _ = @clock.now.getutc.iso8601(6).split("T")
          uuid = ::SecureRandom.uuid

          [
            "dumped-data",
            @s3_file_prefix,
            type,
            "v#{@latest_json_schema_version}",
            date,
            "#{uuid}.jsonl.gz"
          ].join("/")
        end

        def build_jsonl_file_from(operations)
          operation_payloads = operations
            .select { |op| op.update_target.type == op.event.fetch("type") }
            .reject { |op| op.to_datastore_bulk.empty? }
            .map do |op|
              _, payload_body = op.to_datastore_bulk
              params = payload_body.fetch(:script).fetch(:params)
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
          gz = ::Zlib::GzipWriter.new(io)

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

