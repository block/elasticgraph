# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/runtime_metadata/schema"

module ElasticGraph
  module ProtoIngestion
    module RuntimeMetadata
      RSpec.describe Schema, ".from_schema_artifacts" do
        it "loads the protobuf metadata registered with the protobuf indexer extension" do
          artifacts = define_proto_schema_results do |schema|
            schema.proto_schema_artifacts package_name: "example"
            define_item_type(schema)
          end

          expect(Schema.from_schema_artifacts(artifacts).package_name).to eq("example")
        end

        it "finds the protobuf metadata when other indexer extensions are registered before it" do
          stub_const("OtherIndexerExtension", ::Module.new)
          artifacts = define_proto_schema_results do |schema|
            # `defined_at` just needs a valid require path, but needs to be outside ElasticGraph
            # to not mess with our code coverage measurement.
            schema.register_indexer_extension OtherIndexerExtension, defined_at: "time"
            schema.proto_schema_artifacts package_name: "example"
            define_item_type(schema)
          end

          expect(Schema.from_schema_artifacts(artifacts).package_name).to eq("example")
        end

        it "raises a clear error when the schema artifacts lack protobuf runtime metadata" do
          artifacts = define_schema(schema_element_name_form: :snake_case) { |schema| define_item_type(schema) }

          expect { Schema.from_schema_artifacts(artifacts) }.to raise_error(
            Errors::ConfigError,
            /Protobuf runtime metadata is missing\. Enable `ElasticGraph::ProtoIngestion::SchemaDefinition::APIExtension`/
          )
        end

        def define_item_type(schema)
          schema.object_type("Item") do |type|
            type.field "id", "ID!"
            type.index "items"
          end
        end
      end
    end
  end
end
