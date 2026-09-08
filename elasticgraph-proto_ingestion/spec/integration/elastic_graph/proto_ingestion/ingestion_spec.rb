# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "aws-sdk-s3"
require "elastic_graph/indexer/indexing_failures_error"
require "elastic_graph/indexer_lambda/sqs_processor"
require "elastic_graph/proto_ingestion/indexing_event_decoder"
require "elastic_graph/spec_support/compiled_proto_support"
require "elastic_graph/warehouse_lambda/warehouse_dumper"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe "Protobuf ingestion", :uses_datastore, :builds_indexer, :builds_graphql, :builds_admin do
      include CompiledProtoSupport

      it "includes source-only types and preserves multi-source updates regardless of arrival order" do
        results = define_proto_schema_results do |s|
          s.object_type "Source" do |t|
            t.field "id", "ID!"
            t.field "product_id", "ID!"
            t.field "name", "String"
          end
          s.object_type "Product" do |t|
            t.field "id", "ID!"
            t.field "label", "String"
            t.relates_to_one "source", "Source", via: "product_id", dir: :in, indexing_only: true
            t.field("source_name", "String") { |f| f.sourced_from "source", "name" }
            t.index("unique_index_sourced_products") { |i| i.has_had_multiple_sources! }
          end
        end
        indexer = build_indexer(schema_artifacts: results)
        build_admin(datastore_core: indexer.datastore_core).cluster_configurator.configure_cluster(StringIO.new)
        with_compiled_proto(results) do |pool, path|
          envelope = pool.lookup("elasticgraph.ElasticGraphEventEnvelope").msgclass
          batch = pool.lookup("elasticgraph.ElasticGraphEventBatch").msgclass
          source = envelope.new(op: "upsert", id: "s1", version: 1, record_source: {product_id: "p1", name: "source"})
          product = envelope.new(op: "upsert", id: "p1", version: 1, record_product: {label: "product"})
          decoder = IndexingEventDecoder.new(config: {"descriptor_set_file" => path}, schema_artifacts: results, logger: indexer.logger)
          [source, product, source].each do |event|
            indexer.processor.process(decoder.decode(batch.encode(batch.new(events: [event]))), refresh_indices: true)
          end
          graphql = build_graphql(datastore_core: indexer.datastore_core)
          expect(graphql.graphql_query_executor.execute("{ products { nodes { id label source_name } } }").dig("data", "products", "nodes"))
            .to eq([{"id" => "p1", "label" => "product", "source_name" => "source"}])
        end
      end

      [:proto2, :proto3].each do |syntax|
        [:snake_case, :camelCase].each do |casing|
          context "with #{syntax} and #{casing}" do
            let(:results) do
              define_proto_schema_results(schema_element_name_form: casing) do |s|
                s.proto_schema_artifacts package_name: "events.v1", syntax: syntax
                s.enum_type("Status") { |t| t.values "ACTIVE", "RETIRED" }
                s.object_type "Details" do |t|
                  t.field "label", "String", name_in_index: "private_label"
                  t.field "status", "Status"
                end
                s.object_type "Product" do |t|
                  t.field "id", "ID!"
                  t.field "name", "String", name_in_index: "private_name"
                  t.field "enabled", "Boolean"
                  t.field "quantity", "Int"
                  t.field "created", "DateTime"
                  t.field "weight", "LongString"
                  t.field "untyped", "Untyped"
                  t.field "details", "Details"
                  t.field "tags", "[String!]!"
                  t.field "matrix", "[[Float!]!]!"
                  t.index "unique_index_products"
                end
              end
            end

            let(:indexer) { build_indexer(schema_artifacts: results) }
            let(:graphql) { build_graphql(datastore_core: indexer.datastore_core) }

            before do
              build_admin(datastore_core: indexer.datastore_core).cluster_configurator.configure_cluster(StringIO.new)
            end

            it "indexes real protobuf batches and queries the indexed values without JSON schema artifacts" do
              expect(results).not_to respond_to(:json_schemas_for)
              with_compiled_proto(results) do |pool, descriptor_file|
                product = pool.lookup("events.v1.Product").msgclass
                envelope = pool.lookup("events.v1.ElasticGraphEventEnvelope").msgclass
                batch = pool.lookup("events.v1.ElasticGraphEventBatch").msgclass
                decoder = IndexingEventDecoder.new(config: {"descriptor_set_file" => descriptor_file}, schema_artifacts: results, logger: indexer.logger)
                record = product.new(name: "new", enabled: false, quantity: 0, weight: 9223372036854775807,
                  untyped: '{"n":3.0}', created: {seconds: 1704067200, nanos: 123000000},
                  details: {label: "detail", status: :STATUS_ACTIVE}, tags: ["one", "two"], matrix: [{values: [1.0, 2.0]}, {values: []}])
                payload = batch.encode(batch.new(events: [envelope.new(op: "upsert", id: "p1", version: 2, record_product: record)]))
                indexer.processor.process(decoder.decode(payload), refresh_indices: true)
                # Replaying an older record must not regress the index.
                old_payload = batch.encode(batch.new(events: [envelope.new(op: "upsert", id: "p1", version: 1, record_product: product.new(name: "old"))]))
                indexer.processor.process(decoder.decode(old_payload), refresh_indices: true)
                query = "{ products { nodes { id name enabled quantity created weight untyped details { label status } tags } } }"
                response = graphql.graphql_query_executor.execute(query)
                expect(response.fetch("data").fetch("products").fetch("nodes")).to eq([{
                  "id" => "p1", "name" => "new", "enabled" => false, "quantity" => 0,
                  "created" => "2024-01-01T00:00:00.123Z", "weight" => "9223372036854775807",
                  "untyped" => {"n" => 3.0}, "details" => {"label" => "detail", "status" => "ACTIVE"}, "tags" => ["one", "two"]
                }])
                expect(results.proto_schema).not_to include("private_name", "private_label")
              end
            end

            it "passes SQS attributes to the raw decoder and returns only failed message IDs" do
              with_compiled_proto(results) do |pool, descriptor_file|
                product = pool.lookup("events.v1.Product").msgclass
                configured_indexer = build_indexer(datastore_core: indexer.datastore_core, indexing_event_decoder: {
                  "name" => "ElasticGraph::ProtoIngestion::IndexingEventDecoder",
                  "require_path" => "elastic_graph/proto_ingestion/indexing_event_decoder",
                  "config" => {"descriptor_set_file" => descriptor_file, "format" => "raw", "encoding" => "base64"}
                })
                sqs_processor = IndexerLambda::SqsProcessor.new(configured_indexer.processor, logger: indexer.logger,
                  ignore_sqs_latency_timestamps_from_arns: [], indexing_event_decoder: configured_indexer.indexing_event_decoder)
                body = Base64.strict_encode64(product.encode(product.new(name: "SQS")))
                properties = {"eg_op" => "upsert", "eg_type" => "Product", "eg_id" => "sqs1", "eg_version" => "1"}
                sqs_record = {"body" => body, "messageId" => "good", "eventSourceARN" => "arn:aws:sqs:us-west-2:123:events",
                              "messageAttributes" => properties.transform_values { |value| {"stringValue" => value, "dataType" => "String"} }}
                bad_record = sqs_record.merge("messageId" => "bad", "messageAttributes" => properties.merge("eg_op" => "delete").transform_values { |value| {"stringValue" => value} })
                response = nil
                expect {
                  response = sqs_processor.process({"Records" => [sqs_record, bad_record]}, refresh_indices: true)
                }.to log_warning(a_string_including("FailedEventOperationBuildingFailure"))
                expect(response).to eq({"batchItemFailures" => [{"itemIdentifier" => "bad"}]})
                expect(graphql.graphql_query_executor.execute("{ products { nodes { id name } } }").dig("data", "products", "nodes"))
                  .to eq([{"id" => "sqs1", "name" => "SQS"}])
              end
            end

            it "writes protobuf records to an unversioned warehouse partition through the shared processor" do
              with_compiled_proto(results) do |pool, descriptor_file|
                product = pool.lookup("events.v1.Product").msgclass
                s3 = Aws::S3::Client.new(stub_responses: true)
                dumper = WarehouseLambda::WarehouseDumper.new(logger: indexer.logger, s3_client: s3,
                  s3_bucket_name: "events", s3_file_prefix: "warehouse", clock: Time)
                warehouse_indexer = build_indexer(datastore_core: indexer.datastore_core, datastore_router: dumper)
                decoder = IndexingEventDecoder.new(config: {"descriptor_set_file" => descriptor_file, "format" => "raw"}, schema_artifacts: results, logger: indexer.logger)
                events = decoder.decode_with_metadata(product.encode(product.new(name: "warehouse", untyped: '{"n":3.0}')),
                  metadata: {"eg_op" => "upsert", "eg_type" => "Product", "eg_id" => "w1", "eg_version" => "7"})
                warehouse_indexer.processor.process(events)
                upload = s3.api_requests.find { |request| request.fetch(:operation_name) == :put_object }.fetch(:params)
                expect(upload.fetch(:key)).to start_with("warehouse/Product/unversioned/")
                rows = Zlib::GzipReader.new(StringIO.new(upload.fetch(:body))).read.lines.map { |line| JSON.parse(line) }
                expect(rows).to contain_exactly(a_hash_including("id" => "w1", "private_name" => "warehouse", "__eg_version" => 7, "untyped" => '{"n":3.0}'))
              end
            end

            it "accepts raw records with transport properties and isolates invalid envelopes" do
              with_compiled_proto(results) do |pool, descriptor_file|
                product = pool.lookup("events.v1.Product").msgclass
                decoder = IndexingEventDecoder.new(config: {"descriptor_set_file" => descriptor_file, "format" => "raw", "encoding" => "base64"}, schema_artifacts: results, logger: indexer.logger)
                payload = Base64.strict_encode64(product.encode(product.new(name: "raw")))
                properties = {"eg_op" => "upsert", "eg_type" => "Product", "eg_id" => "p2", "eg_version" => "3"}
                events = decoder.decode_with_metadata(payload, metadata: properties)
                expect(events.first).not_to include("schema_version", "json_schema_version")
                failures = nil
                expect {
                  failures = indexer.processor.process_returning_failures(events + decoder.decode_with_metadata(payload, metadata: properties.merge("eg_version" => "bad")), refresh_indices: true)
                }.to log_warning(a_string_including("FailedEventOperationBuildingFailure"))
                expect(failures.size).to eq(1)
                expect(failures.first.message).to include("version must be a positive integer")
                response = graphql.graphql_query_executor.execute("{ products { nodes { id name } } }")
                expect(response.dig("data", "products", "nodes")).to eq([{"id" => "p2", "name" => "raw"}])
              end
            end
          end
        end
      end
    end
  end
end
