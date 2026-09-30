# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe "Generated protobuf schemas", :in_temp_dir do
        [:proto2, :proto3].each do |syntax|
          context "with #{syntax}" do
            attr_reader :proto

            before(:context) do
              @proto = define_proto_schema do |s|
                s.proto_schema_artifacts package_name: "elasticgraph", syntax: syntax
                s.object_type "Product" do |t|
                  t.field "id", "ID!"
                  t.field "name", "String"
                  t.field "enabled", "Boolean"
                  t.field "quantity", "Int"
                  t.field "matrix", "[[Int!]!]!"
                  t.field "cube", "[[[Int!]!]!]!"
                  t.field "details", "ProductDetails"
                  t.index "products"
                end
                s.object_type("ProductDetails") { |t| t.field "label", "String" }
              end
            end

            let(:text_formatted_message) do
              <<~PROTO
                id: "record"
                name: ""
                enabled: false
                quantity: 0
                matrix { values: 1 values: 2 }
                matrix {}
                cube { values { values: 3 } values {} }
                details { label: "nested record" }
              PROTO
            end

            it "preserves explicit default values on the wire" do
              expect(encode_and_decode(text_formatted_message)).to include(
                'name: ""',
                "enabled: false",
                "quantity: 0",
                'label: "nested record"'
              )
            end

            it "preserves nested lists on the wire" do
              expect(encode_and_decode(text_formatted_message)).to include(
                "matrix {\n  values: 1\n  values: 2\n}\nmatrix {\n}",
                "cube {\n  values {\n    values: 3\n  }\n  values {\n  }\n}"
              )
            end

            it "roundtrips an empty message" do
              expect(encode_and_decode("")).to eq("")
            end

            it "round trips timestamp metadata and a record through protoc" do
              input = 'latency_timestamps { key: "published" value { seconds: 1709251199 nanos: 123456789 } } product { id: "p1" }'
              encoded = run_protoc(proto, "--encode=elasticgraph.ElasticGraphEventEnvelope", input)
              decoded = run_protoc(proto, "--decode=elasticgraph.ElasticGraphEventEnvelope", encoded)
              expect(decoded).to include('key: "published"', "seconds: 1709251199", "nanos: 123456789", 'id: "p1"')
            end
          end
        end

        def encode_and_decode(text_formatted_message)
          encoded = run_protoc(proto, "--encode=elasticgraph.Product", text_formatted_message)
          run_protoc(proto, "--decode=elasticgraph.Product", encoded)
        end
      end
    end
  end
end
