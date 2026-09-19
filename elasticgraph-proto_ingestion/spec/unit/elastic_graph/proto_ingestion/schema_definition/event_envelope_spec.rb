# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/schema"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe "Protobuf event envelope" do
        it "omits the envelope when no types are ingestible" do
          results = define_proto_schema_results { |schema| schema.object_type("Product") { |type| type.field "id", "ID!" } }
          expect(results.proto_envelope_schema).to eq("")
        end

        it "reserves removed envelope variants and reuses their numbers when restored" do
          define_types = lambda do |schema, names|
            names.each do |name|
              schema.object_type(name) do |type|
                type.field "id", "ID"
                type.index name.downcase
              end
            end
          end

          old = define_proto_schema_results { |schema| define_types.call(schema, ["Apple", "Pear"]) }
          current = define_proto_schema_results(old) { |schema| define_types.call(schema, ["Pear"]) }
          expect(current.proto_envelope_schema).to include("reserved 5; // Previously used by record_apple.", "record_pear = 6;")

          restored = define_proto_schema_results(current) { |schema| define_types.call(schema, ["Pear", "Apple"]) }
          expect(restored.proto_envelope_schema).to include("record_apple = 5;", "record_pear = 6;").and exclude("reserved 5;")
        end

        it "rejects type names that produce the same envelope field name" do
          results = define_proto_schema_results do |schema|
            %w[MyProduct My_Product].each_with_index do |name, i|
              schema.object_type(name) do |type|
                type.field "id", "ID!"
                type.index "products#{i}"
              end
            end
          end
          expect { results.proto_envelope_schema }.to raise_error(Errors::SchemaError, /distinct.*snake_case/)
        end
      end
    end
  end
end
