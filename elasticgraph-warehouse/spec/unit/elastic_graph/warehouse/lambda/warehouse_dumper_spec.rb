# Copyright 2024 - 2025 Block, Inc.
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
require "elastic_graph/warehouse/lambda"
require "elastic_graph/warehouse/lambda/warehouse_dumper"
require "elastic_graph/warehouse/lambda/config"

module ElasticGraph
  module Warehouse
    class Lambda
      RSpec.describe WarehouseDumper do
        include_context "lambda function", config_overrides_in_yaml: {"warehouse" => {"s3_path_prefix" => "Data001"}}

        let(:indexer) { ::ElasticGraph::Indexer.from_parsed_yaml(CommonSpecHelpers.parsed_test_settings_yaml) }
        let(:s3_client) { ::Aws::S3::Client.new(stub_responses: true) }
        let(:s3_bucket_name) { "warehouse-bucket" }
        let(:clock) { class_double(::Time, now: ::Time.utc(2024, 9, 15, 12, 30, 12.123454)) }

        let(:warehouse_lambda) do
          Lambda.new(
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

        it "writes to S3" do
          operations = [widget_primary_indexing_op]

          results = warehouse_dumper.bulk(operations)

          expect(results).to be_a ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult
          expect(s3_client.api_requests.map { |req| req[:operation_name] }).to eq [:put_object]

          params = s3_client.api_requests.first.fetch(:params)
          expect(params[:bucket]).to eq s3_bucket_name
          expect(params[:key]).to match %r{dumped-data/Data001/Widget/v1/2024-09-15/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl\.gz}

          data = params.fetch(:body)
            .then { |data| ::Zlib::GzipReader.new(StringIO.new(data)).read }
            .then { |data| ::JSON.parse(data) }

          expect(data).to include("id" => "1", "__eg_version" => 3)
        end

        it "raises an S3OperationFailedError when S3 put_object fails" do
          s3_client.stub_responses(:put_object, "ServiceError")

          expect {
            warehouse_dumper.bulk([widget_primary_indexing_op])
          }.to raise_error(::ElasticGraph::Errors::S3OperationFailedError, /Failed to write warehouse data to S3/)
        end

        it "skips operations where update_target.type does not match event type (derived indexing operations)" do
          # Create a derived indexing operation where update_target.type differs from the event type
          derived_op = new_derived_indexing_op({
            "type" => "Widget",
            "id" => "1",
            "version" => 3,
            "record" => {"id" => "1", "dayOfWeek" => "MON", "created_at" => "2024-09-15T12:30:12Z", "workspace_id" => "ws-1"}
          })

          results = warehouse_dumper.bulk([derived_op])

          # The operation should still return a successful result, but no data should be written
          expect(results).to be_a ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult
          expect(s3_client.api_requests.map { |req| req[:operation_name] }).to eq [:put_object]

          # The JSONL file should be empty (just the header without data)
          data = s3_client.api_requests.first.fetch(:params).fetch(:body)
            .then { |data| ::Zlib::GzipReader.new(StringIO.new(data)).read }

          expect(data).to eq("")
        end

        it "skips operations with empty datastore_bulk payloads" do
          # Create a mock operation that returns empty datastore_bulk
          empty_op = instance_double(
            ::ElasticGraph::Indexer::Operation::Update,
            event: {"type" => "Widget"},
            update_target: instance_double("UpdateTarget", type: "Widget"),
            to_datastore_bulk: []
          )

          results = warehouse_dumper.bulk([empty_op])

          expect(results).to be_a ::ElasticGraph::Indexer::DatastoreIndexingRouter::BulkResult
          expect(s3_client.api_requests.map { |req| req[:operation_name] }).to eq [:put_object]

          # The JSONL file should be empty
          data = s3_client.api_requests.first.fetch(:params).fetch(:body)
            .then { |data| ::Zlib::GzipReader.new(StringIO.new(data)).read }

          expect(data).to eq("")
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

        def new_derived_indexing_op(event)
          # Find an update target where the type differs from the event type (derived indexing)
          update_targets = indexer
            .schema_artifacts
            .runtime_metadata
            .object_types_by_name
            .fetch(event.fetch("type"))
            .update_targets
            .reject { |ut| ut.type == event.fetch("type") }

          expect(update_targets).not_to be_empty
          update_target = update_targets.first
          index_def = indexer.datastore_core.index_definitions_by_graphql_type.fetch(update_target.type).first

          ::ElasticGraph::Indexer::Operation::Update.new(
            event: event,
            prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
              event.fetch("type"),
              event.fetch("record")
            ),
            destination_index_def: index_def,
            update_target: update_target,
            doc_id: event.fetch("id"),
            destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
          )
        end
      end
    end
  end
end
