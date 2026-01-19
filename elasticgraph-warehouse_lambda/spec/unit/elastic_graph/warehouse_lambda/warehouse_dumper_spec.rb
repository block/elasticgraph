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

module ElasticGraph
  class WarehouseLambda
    RSpec.describe WarehouseDumper, :capture_logs do
      include BuildsWarehouseLambda

      let(:s3_client) { ::Aws::S3::Client.new(stub_responses: true) }
      let(:s3_bucket_name) { "warehouse-bucket" }
      let(:clock) { class_double(::Time, now: ::Time.utc(2024, 9, 15, 12, 30, 12.123454)) }
      let(:warehouse_lambda) { build_warehouse_lambda(s3_client: s3_client, clock: clock, s3_bucket_name: s3_bucket_name) }
      let(:warehouse_dumper) { warehouse_lambda.warehouse_dumper }
      let(:indexer) { warehouse_lambda.indexer }

      let(:widget_primary_indexing_op) do
        new_primary_indexing_op({
          "type" => "Widget",
          "id" => "1",
          "version" => 3,
          "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
        })
      end

      it "writes operations to S3 as gzipped JSONL files and returns success results" do
        op1 = new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 3, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        op2 = new_primary_indexing_op({"type" => "Widget", "id" => "2", "version" => 5, "record" => {"id" => "2", "dayOfWeek" => "TUE", "created_at" => "2024-09-15T13:30:12Z", "workspace_id" => "ws-2"}})
        operations = [op1, op2]

        results = warehouse_dumper.bulk(operations)

        # Verify S3 upload
        expect(s3_client.api_requests.map { |req| req[:operation_name] }).to eq [:put_object]

        # Verify S3 upload parameters
        params = s3_client.api_requests.first.fetch(:params)
        expect(params[:bucket]).to eq s3_bucket_name
        expect(params[:key]).to match %r{Data001/Widget/v1/2024-09-15/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl\.gz}
        expect(params[:checksum_algorithm]).to eq "sha256"
        expect(params[:if_none_match]).to eq "*"

        # Verify compression (gzip actually reduces size)
        compressed_body = params[:body]
        jsonl_content = ::Zlib::GzipReader.new(StringIO.new(compressed_body)).read
        expect(compressed_body.bytesize).to be < jsonl_content.bytesize

        # Verify JSONL content has both records
        lines = jsonl_content.split("\n")
        expect(lines.size).to eq 2

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
          expect(result).to be_a ::ElasticGraph::Indexer::Operation::Result
          expect(result.category).to eq :success
        end
      end

      it "writes operations of different types to separate S3 files" do
        widget_op = new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 3, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        component_op = new_primary_indexing_op({"type" => "Component", "id" => "c1", "version" => 2, "record" => {"id" => "c1", "created_at" => "2024-09-15T12:30:12Z"}})
        operations = [widget_op, component_op]

        warehouse_dumper.bulk(operations)

        expect(s3_client.api_requests.size).to eq 2
        keys = s3_client.api_requests.map { |req| req[:params][:key] }

        expect(keys[0]).to match %r{Data001/Widget/v1/2024-09-15/}
        expect(keys[1]).to match %r{Data001/Component/v1/2024-09-15/}
      end

      it "logs structured information about received batch and dumped files" do
        widget_op = new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 3, "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}})
        component_op = new_primary_indexing_op({"type" => "Component", "id" => "c1", "version" => 2, "record" => {"id" => "c1", "created_at" => "2024-09-15T12:30:12Z"}})
        operations = [widget_op, component_op]

        warehouse_dumper.bulk(operations)

        expect(logged_jsons_of_type(WarehouseDumper::LOG_MSG_RECEIVED_BATCH)).to match [a_hash_including({
          "record_counts_by_type" => {"Widget" => 1, "Component" => 1}
        })]

        expect(logged_jsons_of_type(WarehouseDumper::LOG_MSG_DUMPED_FILE)).to match [
          a_hash_including({
            "s3_bucket" => s3_bucket_name,
            "type" => "Widget",
            "record_count" => 1
          }),
          a_hash_including({
            "s3_bucket" => s3_bucket_name,
            "type" => "Component",
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

      it "skips operations with empty to_datastore_bulk" do
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

        # Verify only one record in the JSONL
        params = s3_client.api_requests.first.fetch(:params)
        jsonl_content = ::Zlib::GzipReader.new(StringIO.new(params[:body])).read
        lines = jsonl_content.split("\n")

        expect(lines.size).to eq 1
        record = ::JSON.parse(lines[0])
        expect(record["id"]).to eq "1"
      end

      it "handles empty operations list without creating S3 files" do
        warehouse_dumper.bulk([])

        expect(s3_client.api_requests).to be_empty
      end

      it "skips S3 upload when all operations are filtered out (derived index operations)" do
        # Create an operation where update_target.type != event type (simulates derived index)
        widget_op = new_primary_indexing_op({
          "type" => "Widget",
          "id" => "1",
          "version" => 3,
          "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
        })

        # Stub the update_target to return a different type
        derived_update_target = instance_double("ElasticGraph::SchemaArtifacts::RuntimeMetadata::UpdateTarget", type: "WidgetDerived")
        allow(widget_op).to receive(:update_target).and_return(derived_update_target)

        warehouse_dumper.bulk([widget_op])

        # Should not create any S3 files when all operations are filtered
        expect(s3_client.api_requests).to be_empty
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
          destination_index_def: index_def,
          update_target: update_targets.first,
          doc_id: event.fetch("id"),
          destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
        )
      end
    end
  end
end
