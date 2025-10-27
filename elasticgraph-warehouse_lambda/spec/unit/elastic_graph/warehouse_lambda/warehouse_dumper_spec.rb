# frozen_string_literal: true
# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
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
