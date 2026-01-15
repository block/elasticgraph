# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/lambda_function"

require "aws-sdk-s3"
require "elastic_graph/indexer"
require "elastic_graph/indexer/operation/update"
require "elastic_graph/warehouse_lambda"
require "elastic_graph/warehouse_lambda/warehouse_dumper"
require "elastic_graph/warehouse_lambda/config"

module ElasticGraph
  class WarehouseLambda
    RSpec.describe WarehouseDumper do
      include_context "lambda function", config_overrides_in_yaml: {"warehouse" => {"s3_path_prefix" => "Data001"}}

      let(:indexer) { ::ElasticGraph::Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml) }
      let(:s3_client) { ::Aws::S3::Client.new(stub_responses: true) }
      let(:s3_bucket_name) { "warehouse-bucket" }
      let(:clock) { class_double(::Time, now: ::Time.utc(2024, 9, 15, 12, 30, 12.123454)) }

      let(:warehouse_lambda) do
        WarehouseLambda.new(
          config: Config.new(s3_path_prefix: "Data001"),
          indexer: indexer,
          s3_client: s3_client,
          s3_bucket_name: s3_bucket_name,
          clock: clock
        )
      end

      let(:warehouse_dumper) { warehouse_lambda.warehouse_dumper }
      let(:widget_primary_indexing_op) do
        new_primary_indexing_op({
          "type" => "Widget",
          "id" => "1",
          "version" => 3,
          "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
        })
      end

      it "writes a single operation to S3 with correct format and content" do
        operations = [widget_primary_indexing_op]

        results = warehouse_dumper.bulk(operations)

        expect(results).to be_a ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult
        expect(s3_client.api_requests.map { |req| req[:operation_name] }).to eq [:put_object]

        params = s3_client.api_requests.first.fetch(:params)
        expect(params[:bucket]).to eq s3_bucket_name
        expect(params[:key]).to match %r{dumped-data/Data001/Widget/v1/2024-09-15/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl\.gz}
        expect(params[:checksum_algorithm]).to eq "sha256"
        expect(params[:if_none_match]).to eq "*"

        data = params.fetch(:body)
          .then { |data| ::Zlib::GzipReader.new(StringIO.new(data)).read }
          .then { |data| ::JSON.parse(data) }

        expect(data).to include("id" => "1", "__eg_version" => 3)
        expect(data.keys).to include("created_at", "workspace_id2") # Verify schema fields are present
      end

      it "writes multiple operations of the same type to a single JSONL file" do
        op1 = new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 3, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        op2 = new_primary_indexing_op({"type" => "Widget", "id" => "2", "version" => 5, "record" => {"id" => "2", "dayOfWeek" => "TUE", "created_at" => "2024-09-15T13:30:12Z", "workspace_id" => "ws-2"}})
        operations = [op1, op2]

        warehouse_dumper.bulk(operations)

        expect(s3_client.api_requests.size).to eq 1
        params = s3_client.api_requests.first.fetch(:params)

        jsonl_content = ::Zlib::GzipReader.new(StringIO.new(params[:body])).read
        lines = jsonl_content.split("\n")
        expect(lines.size).to eq 2

        record1 = ::JSON.parse(lines[0])
        record2 = ::JSON.parse(lines[1])

        expect(record1).to include("id" => "1", "__eg_version" => 3)
        expect(record1["created_at"]).to eq "2024-09-15T12:30:12.000Z"

        expect(record2).to include("id" => "2", "__eg_version" => 5)
        expect(record2["created_at"]).to eq "2024-09-15T13:30:12.000Z"
      end

      it "writes operations of different types to separate S3 files" do
        widget_op = new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 3, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        component_op = new_primary_indexing_op({"type" => "Component", "id" => "c1", "version" => 2, "record" => {"id" => "c1", "created_at" => "2024-09-15T12:30:12Z"}})
        operations = [widget_op, component_op]

        warehouse_dumper.bulk(operations)

        expect(s3_client.api_requests.size).to eq 2
        keys = s3_client.api_requests.map { |req| req[:params][:key] }

        expect(keys[0]).to match %r{dumped-data/Data001/Widget/v1/2024-09-15/}
        expect(keys[1]).to match %r{dumped-data/Data001/Component/v1/2024-09-15/}
      end

      it "returns success results for all operations" do
        op1 = new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 3, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        op2 = new_primary_indexing_op({"type" => "Component", "id" => "c1", "version" => 2, "record" => {"id" => "c1", "created_at" => "2024-09-15T12:30:12Z"}})
        operations = [op1, op2]

        results = warehouse_dumper.bulk(operations)

        expect(results.ops_and_results_by_cluster.keys).to eq ["warehouse"]
        ops_and_results = results.ops_and_results_by_cluster.fetch("warehouse")
        expect(ops_and_results.size).to eq 2

        ops_and_results.each do |op, result|
          expect(operations).to include(op)
          expect(result).to be_a ::ElasticGraph::Indexer::Operation::Result
          expect(result.category).to eq :success
        end
      end

      it "logs structured information about received batch and dumped files" do
        widget_op = new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 3, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        component_op = new_primary_indexing_op({"type" => "Component", "id" => "c1", "version" => 2, "record" => {"id" => "c1", "created_at" => "2024-09-15T12:30:12Z"}})
        operations = [widget_op, component_op]

        logger = instance_double(::Logger)
        allow(warehouse_lambda).to receive(:logger).and_return(logger)

        expect(logger).to receive(:info).with(hash_including(
          "message_type" => "WarehouseLambdaReceivedBatch",
          "record_counts_by_type" => {"Widget" => 1, "Component" => 1}
        ))

        expect(logger).to receive(:info).with(hash_including(
          "message_type" => "DumpedToWarehouseFile",
          "s3_bucket" => s3_bucket_name,
          "type" => "Widget",
          "record_count" => 1
        )).once

        expect(logger).to receive(:info).with(hash_including(
          "message_type" => "DumpedToWarehouseFile",
          "s3_bucket" => s3_bucket_name,
          "type" => "Component",
          "record_count" => 1
        )).once

        warehouse_dumper.bulk(operations)
      end

      it "compresses JSONL data with gzip" do
        operations = [widget_primary_indexing_op]

        warehouse_dumper.bulk(operations)

        params = s3_client.api_requests.first.fetch(:params)
        compressed_body = params[:body]

        # Verify it's actually gzipped by decompressing it
        uncompressed = ::Zlib::GzipReader.new(StringIO.new(compressed_body)).read
        expect(uncompressed).to include('"id":"1"')

        # Verify compression actually reduces size for realistic data
        expect(compressed_body.bytesize).to be < uncompressed.bytesize
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

      it "ignores the refresh parameter (not applicable for S3 writes)" do
        operations = [widget_primary_indexing_op]

        # Should succeed with refresh: true
        results_with_refresh = warehouse_dumper.bulk(operations, refresh: true)
        expect(results_with_refresh).to be_a ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult

        # Should succeed with refresh: false (same behavior)
        s3_client.api_requests.clear
        results_without_refresh = warehouse_dumper.bulk(operations, refresh: false)
        expect(results_without_refresh).to be_a ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult

        # Both should write to S3 regardless of refresh parameter
        expect(s3_client.api_requests.size).to eq 1
      end

      it "propagates S3 errors when upload fails" do
        s3_client.stub_responses(:put_object, "ServiceUnavailable")
        operations = [widget_primary_indexing_op]

        expect {
          warehouse_dumper.bulk(operations)
        }.to raise_error(Aws::S3::Errors::ServiceUnavailable)
      end

      it "handles operations with empty to_datastore_bulk by skipping them" do
        # Create two Widget operations - one valid, one with empty datastore_bulk
        valid_widget = new_primary_indexing_op({
          "type" => "Widget",
          "id" => "1",
          "version" => 3,
          "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
        })

        empty_widget = new_primary_indexing_op({
          "type" => "Widget",
          "id" => "2",
          "version" => 4,
          "record" => {"id" => "2", "dayOfWeek" => "TUE", "created_at" => "2024-09-15T13:30:12Z", "workspace_id" => "ws-2"}
        })

        # Stub to_datastore_bulk to return empty on empty_widget
        allow(empty_widget).to receive(:to_datastore_bulk).and_return([])

        warehouse_dumper.bulk([valid_widget, empty_widget])

        # Should write one Widget file with only the valid widget (empty_widget filtered out)
        expect(s3_client.api_requests.size).to eq 1

        params = s3_client.api_requests.first[:params]
        jsonl_content = ::Zlib::GzipReader.new(StringIO.new(params[:body])).read
        lines = jsonl_content.split("\n")

        # Should only have 1 line (the valid widget), not 2
        expect(lines.size).to eq 1
        record = ::JSON.parse(lines[0])
        expect(record["id"]).to eq "1"
      end

      it "handles operations where update_target type differs from event type by skipping them" do
        # This tests the filter: op.update_target.type == op.event.fetch("type")
        # Such operations represent derived indices that shouldn't be exported to the warehouse
        valid_widget = new_primary_indexing_op({
          "type" => "Widget",
          "id" => "1",
          "version" => 3,
          "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
        })

        derived_widget = new_primary_indexing_op({
          "type" => "Widget",
          "id" => "2",
          "version" => 4,
          "record" => {"id" => "2", "dayOfWeek" => "TUE", "created_at" => "2024-09-15T13:30:12Z", "workspace_id" => "ws-2"}
        })

        # Stub update_target to return a different type on derived_widget
        different_type_target = instance_double("UpdateTarget", type: "DerivedWidget")
        allow(derived_widget).to receive(:update_target).and_return(different_type_target)

        warehouse_dumper.bulk([valid_widget, derived_widget])

        # Should write one Widget file with only the valid widget (derived_widget filtered out)
        expect(s3_client.api_requests.size).to eq 1

        params = s3_client.api_requests.first[:params]
        jsonl_content = ::Zlib::GzipReader.new(StringIO.new(params[:body])).read
        lines = jsonl_content.split("\n")

        # Should only have 1 line (the valid widget), not 2
        expect(lines.size).to eq 1
        record = ::JSON.parse(lines[0])
        expect(record["id"]).to eq "1"
      end

      it "handles empty operations array gracefully" do
        results = warehouse_dumper.bulk([])

        expect(results).to be_a ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult
        expect(s3_client.api_requests).to be_empty
        expect(results.ops_and_results_by_cluster.fetch("warehouse")).to eq []
      end

      def new_primary_indexing_op(event)
        update_targets = indexer
          .schema_artifacts
          .runtime_metadata
          .object_types_by_name
          .fetch(event.fetch("type"))
          .update_targets
          .select { |ut| ut.type == event.fetch("type") }

        expect(update_targets.size).to eq(1)
        index_def = indexer.datastore_core.index_definitions_by_graphql_type.fetch(event.fetch("type")).first

        ::ElasticGraph::Indexer::Operation::Update.new(
          event: event,
          prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
            event.fetch("type"),
            event.fetch("record")
          ),
          update_target: update_targets.first,
          destination_index_def: index_def,
          doc_id: event.fetch("id"),
          destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
        )
      end
    end
  end
end
