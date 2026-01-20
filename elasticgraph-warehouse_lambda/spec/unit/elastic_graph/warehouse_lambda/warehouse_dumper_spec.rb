# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "aws-sdk-s3"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/warehouse_lambda/warehouse_dumper"
require "support/builds_warehouse_lambda"
require "elastic_graph/spec_support/builds_indexer_operation"

module ElasticGraph
  class WarehouseLambda
    RSpec.describe WarehouseDumper, :capture_logs do
      include BuildsWarehouseLambda
      include SpecSupport::BuildsIndexerOperation

      let(:s3_client) { ::Aws::S3::Client.new(stub_responses: true) }
      let(:s3_bucket_name) { "warehouse-bucket" }
      let(:clock) { class_double(::Time, now: ::Time.utc(2024, 9, 15, 12, 30, 12.123454)) }
      let(:warehouse_lambda) { build_warehouse_lambda(s3_client: s3_client, clock: clock, s3_bucket_name: s3_bucket_name) }
      let(:warehouse_dumper) { warehouse_lambda.warehouse_dumper }
      let(:indexer) { warehouse_lambda.indexer }

      let(:widget_primary_indexing_op) do
        new_primary_indexing_operation({
          "type" => "Widget",
          "id" => "1",
          "version" => 3,
          "json_schema_version" => 1,
          "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
        })
      end

      it "writes operations to S3 as gzipped JSONL files and returns success results" do
        op1 = new_primary_indexing_operation({"type" => "Widget", "id" => "1", "version" => 3, "json_schema_version" => 1, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        op2 = new_primary_indexing_operation({"type" => "Widget", "id" => "2", "version" => 5, "json_schema_version" => 2, "record" => {"id" => "2", "dayOfWeek" => "TUE", "created_at" => "2024-09-15T13:30:12Z", "workspace_id" => "ws-2"}})
        operations = [op1, op2]

        results = warehouse_dumper.bulk(operations)

        # Verify S3 uploads - should have 2 files (one for json_schema_version 1, one for json_schema_version 2)
        expect(s3_client.api_requests.map { |req| req[:operation_name] }).to eq [:put_object, :put_object]

        # Verify first file (json_schema_version 1)
        params1 = s3_client.api_requests[0].fetch(:params)
        expect(params1[:bucket]).to eq s3_bucket_name
        expect(params1[:key]).to match %r{Data0001/Widget/v1/2024-09-15/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl\.gz}
        expect(params1[:checksum_algorithm]).to eq "sha256"
        expect(params1[:if_none_match]).to eq "*"

        # Verify compression (gzip actually reduces size)
        compressed_body1 = params1[:body]
        jsonl_content1 = ::Zlib::GzipReader.new(StringIO.new(compressed_body1)).read
        expect(compressed_body1.bytesize).to be < jsonl_content1.bytesize

        # Verify first file has one record
        lines1 = jsonl_content1.split("\n")
        expect(lines1.size).to eq 1

        # Verify second file (json_schema_version 2)
        params2 = s3_client.api_requests[1].fetch(:params)
        expect(params2[:key]).to match %r{Data0001/Widget/v2/2024-09-15/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl\.gz}

        compressed_body2 = params2[:body]
        jsonl_content2 = ::Zlib::GzipReader.new(StringIO.new(compressed_body2)).read

        lines2 = jsonl_content2.split("\n")
        expect(lines2.size).to eq 1

        # Verify both records (combine from both files)
        lines = lines1 + lines2

        record1 = ::JSON.parse(lines[0])
        record2 = ::JSON.parse(lines[1])

        expect(record1).to include("id" => "1", "__eg_version" => 3)
        expect(record1["created_at"]).to eq "2024-09-15T12:30:12.000Z"
        # Verify that name_in_index is used (workspace_id2) not the GraphQL field name (workspace_id)
        expect(record1.keys).to include("workspace_id2")
        expect(record1.keys).not_to include("workspace_id")

        expect(record2).to include("id" => "2", "__eg_version" => 5)
        expect(record2["created_at"]).to eq "2024-09-15T13:30:12.000Z"

        # Verify success results
        expect(results.ops_and_results_by_cluster.keys).to eq ["warehouse"]
        ops_and_results = results.ops_and_results_by_cluster.fetch("warehouse")
        expect(ops_and_results.size).to eq 2

        ops_and_results.each do |op, result|
          expect(operations).to include(op)
          expect(result).to be_a Indexer::Operation::Result
          expect(result.category).to eq :success
        end
      end

      it "writes operations of different types to separate S3 files" do
        widget_op = new_primary_indexing_operation({"type" => "Widget", "id" => "1", "version" => 3, "json_schema_version" => 1, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        component_op = new_primary_indexing_operation({"type" => "Component", "id" => "c1", "version" => 2, "json_schema_version" => 1, "record" => {"id" => "c1", "created_at" => "2024-09-15T12:30:12Z"}})
        operations = [widget_op, component_op]

        warehouse_dumper.bulk(operations)

        expect(s3_client.api_requests.size).to eq 2
        keys = s3_client.api_requests.map { |req| req[:params][:key] }

        expect(keys[0]).to match %r{Data0001/Widget/v1/2024-09-15/}
        expect(keys[1]).to match %r{Data0001/Component/v1/2024-09-15/}
      end

      it "logs structured information about received batch and dumped files" do
        widget_op = new_primary_indexing_operation({"type" => "Widget", "id" => "1", "version" => 3, "json_schema_version" => 1, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        component_op = new_primary_indexing_operation({"type" => "Component", "id" => "c1", "version" => 2, "json_schema_version" => 1, "record" => {"id" => "c1", "created_at" => "2024-09-15T12:30:12Z"}})
        operations = [widget_op, component_op]

        warehouse_dumper.bulk(operations)

        expect(logged_jsons_of_type(WarehouseDumper::LOG_MSG_RECEIVED_BATCH)).to match [a_hash_including({
          "record_counts_by_type" => {"Widget" => 1, "Component" => 1}
        })]

        expect(logged_jsons_of_type(WarehouseDumper::LOG_MSG_DUMPED_FILE)).to match [
          a_hash_including({
            "s3_bucket" => s3_bucket_name,
            "type" => "Widget",
            "json_schema_version" => 1,
            "record_count" => 1
          }),
          a_hash_including({
            "s3_bucket" => s3_bucket_name,
            "type" => "Component",
            "json_schema_version" => 1,
            "record_count" => 1
          })
        ]
      end

      it "generates unique S3 keys using UUIDs" do
        operations1 = [widget_primary_indexing_op]
        operations2 = [widget_primary_indexing_op]

        warehouse_dumper.bulk(operations1)
        warehouse_dumper.bulk(operations2)

        keys = s3_client.api_requests.map { |req| req[:params][:key] }
        expect(keys.size).to eq 2
        expect(keys[0]).not_to eq keys[1]

        # Both should be valid UUIDs in the filename
        keys.each do |key|
          expect(key).to match %r{[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl\.gz$}
        end
      end

      it "returns an empty hash from source_event_versions_in_index" do
        operations = [widget_primary_indexing_op]
        result = warehouse_dumper.source_event_versions_in_index(operations)
        expect(result).to eq({})
      end

      it "propagates S3 errors when upload fails" do
        s3_client.stub_responses(:put_object, "ServiceUnavailable")
        operations = [widget_primary_indexing_op]

        expect {
          warehouse_dumper.bulk(operations)
        }.to raise_error(Aws::S3::Errors::ServiceUnavailable)
      end

      it "handles empty operations list without creating S3 files" do
        warehouse_dumper.bulk([])

        expect(s3_client.api_requests).to be_empty
      end

      it "skips S3 upload when all operations are filtered out (derived index operations)" do
        # Create an operation where update_target.type != event type (simulates derived index)
        widget_op = new_primary_indexing_operation({
          "type" => "Widget",
          "id" => "1",
          "version" => 3,
          "json_schema_version" => 1,
          "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
        })

        # Stub the update_target to return a different type
        derived_update_target = instance_double("ElasticGraph::SchemaArtifacts::RuntimeMetadata::UpdateTarget", type: "WidgetDerived")
        allow(widget_op).to receive(:update_target).and_return(derived_update_target)

        warehouse_dumper.bulk([widget_op])

        # Should not create any S3 files when all operations are filtered
        expect(s3_client.api_requests).to be_empty
      end
    end
  end
end
