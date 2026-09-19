# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "aws-sdk-s3"
require "elastic_graph/indexer_lambda/sqs_processor"
require "elastic_graph/proto_ingestion/indexer"
require "elastic_graph/spec_support/compiled_proto_support"
require "elastic_graph/warehouse_lambda/warehouse_dumper"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe Indexer, :builds_indexer, :capture_logs do
      include CompiledProtoSupport

      let(:results) do
        define_proto_schema_results do |schema|
          schema.object_type "Product" do |type|
            type.field "id", "ID!"
            type.field "name", "String!", name_in_index: "private_name"
            type.index "products"
          end
        end
      end
      let(:s3) { Aws::S3::Client.new(stub_responses: true) }
      let(:base_indexer) do
        router = WarehouseLambda::WarehouseDumper.new(logger: logger, s3_client: s3,
          s3_bucket_name: "events", s3_file_prefix: "warehouse", clock: Time)
        build_indexer(schema_artifacts: results, datastore_router: router)
      end

      around do |example|
        with_compiled_proto(results) do |pool, path|
          @pool = pool
          @descriptor_path = path
          example.run
        end
      end

      it "processes binary batches through validation, record preparation, and warehouse output" do
        indexer = Indexer.new(base_indexer, config: {"descriptor_set_file" => @descriptor_path})
        expect_to_return_non_nil_values_from_all_attributes(indexer)
        indexer.process(batch("valid"))
        expect(uploaded_records).to eq([{"id" => "p1", "private_name" => "valid", "__eg_version" => 1}])
        expect(uploads.fetch(0).fetch(:key)).to start_with("warehouse/Product/unversioned/")
      end

      it "indexes valid records and returns failures from the same batch" do
        indexer = Indexer.new(base_indexer, config: {"descriptor_set_file" => @descriptor_path})
        failures = nil
        expect { failures = indexer.process_returning_failures(batch("valid", nil)) }
          .to log_warning(a_string_including("FailedEventOperationBuildingFailure"))
        expect(failures.map(&:message)).to contain_exactly(a_string_including("record.name must not be null"))
        expect(uploaded_records.map { |record| record.fetch("private_name") }).to eq(["valid"])
      end

      it "raises for invalid records after processing valid records" do
        indexer = Indexer.new(base_indexer, config: {"descriptor_set_file" => @descriptor_path})
        expect {
          expect { indexer.process(batch("valid", nil)) }
            .to raise_error(ElasticGraph::Indexer::IndexingFailuresError, /record.name must not be null/)
        }.to log_warning(a_string_including("FailedEventOperationBuildingFailure"))
        expect(uploaded_records.map { |record| record.fetch("private_name") }).to eq(["valid"])
      end

      it "decodes raw SQS payloads with message attributes and preserves failed message IDs" do
        indexer = Indexer.new(base_indexer, config: {
          "descriptor_set_file" => @descriptor_path, "format" => "raw", "encoding" => "base64"
        })
        product = @pool.lookup("elasticgraph.Product").msgclass
        processor = IndexerLambda::SqsProcessor.new(indexer, ignore_sqs_latency_timestamps_from_arns: Set.new)
        records = ["valid", nil].each_with_index.map do |name, index|
          metadata = {"eg_op" => "upsert", "eg_id" => "p#{index}", "eg_version" => "1", "eg_type" => "Product"}
          {
            "body" => Base64.strict_encode64(product.encode(product.new(name: name))),
            "messageId" => "m#{index}", "eventSourceARN" => "arn:aws:sqs:us-west-2:123:events",
            "messageAttributes" => metadata.transform_values { |value| {"stringValue" => value} }
          }
        end
        response = nil
        expect { response = processor.process({"Records" => records}) }
          .to log_warning(a_string_including("FailedEventOperationBuildingFailure"))
        expect(response).to eq({"batchItemFailures" => [{"itemIdentifier" => "m1"}]})
        expect(uploaded_records.map { |record| record.fetch("private_name") }).to eq(["valid"])
      end

      def batch(*names)
        envelope = @pool.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass
        batch = @pool.lookup("elasticgraph.ElasticGraphEventBatch").msgclass
        events = names.each_with_index.map do |name, index|
          envelope.new(op: "upsert", id: "p#{index + 1}", version: 1, record_product: {name: name})
        end
        batch.encode(batch.new(events: events))
      end

      def uploads
        s3.api_requests.map { |request| request.fetch(:params) }
      end

      def uploaded_records
        uploads.flat_map do |upload|
          Zlib::GzipReader.new(StringIO.new(upload.fetch(:body))).read.lines.map { |line| JSON.parse(line) }
        end
      end
    end
  end
end
