# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "open3"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe "Generated protobuf schemas", :in_temp_dir do
        [:proto2, :proto3].each do |syntax|
          it "compiles #{syntax} source-only types and preserves defaults and nested lists on the wire" do
            proto = define_proto_schema do |s|
              s.proto_schema_artifacts package_name: "elasticgraph", syntax: syntax
              s.object_type "Source" do |t|
                t.field "id", "ID!"
                t.field "product_id", "ID!"
                t.field "name", "String"
                t.field "enabled", "Boolean"
                t.field "quantity", "Int"
                t.field "matrix", "[[Int!]!]!"
                t.field "cube", "[[[Int!]!]!]!"
                t.field "details", "SourceDetails"
              end
              s.object_type("SourceDetails") { |t| t.field "label", "String" }
              s.object_type "Product" do |t|
                t.field "id", "ID!"
                t.relates_to_one "source", "Source", via: "product_id", dir: :in, indexing_only: true
                t.field("source_name", "String") { |f| f.sourced_from "source", "name" }
                t.index("products") { |i| i.has_had_multiple_sources! }
              end
            end
            File.write("schema.proto", proto)
            source = <<~PROTO
              id: "source"
              product_id: "product"
              name: ""
              enabled: false
              quantity: 0
              matrix { values: 1 values: 2 }
              matrix {}
              cube { values { values: 3 } values {} }
              details { label: "nested source" }
            PROTO
            encoded = run_protoc("--encode=elasticgraph.Source", source)
            decoded = run_protoc("--decode=elasticgraph.Source", encoded)
            expect(decoded).to include('name: ""', "enabled: false", "quantity: 0", 'label: "nested source"')
            expect(decoded).to include("matrix {\n  values: 1\n  values: 2\n}\nmatrix {\n}")
            expect(decoded).to include("cube {\n  values {\n    values: 3\n  }\n  values {\n  }\n}")
            expect(run_protoc("--decode=elasticgraph.Source", run_protoc("--encode=elasticgraph.Source", ""))).to eq("")
          end
        end

        def run_protoc(operation, input)
          output, errors, status = Open3.capture3(ENV.fetch("PROTOC", "protoc"), "--proto_path=.", operation, "schema.proto", stdin_data: input, binmode: true)
          expect(status.success?).to be(true), errors
          output
        end
      end
    end
  end
end
