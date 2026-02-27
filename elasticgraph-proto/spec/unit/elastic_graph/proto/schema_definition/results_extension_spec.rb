# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto/schema_definition/results_extension"

module ElasticGraph
  module Proto
    module SchemaDefinition
      RSpec.describe ResultsExtension do
        def build_results_with_api(api)
          state = ::Struct.new(:api).new(api)

          ::Object.new.tap do |results|
            results.extend(ResultsExtension)
            results.define_singleton_method(:state) { state }
          end
        end

        it "builds schema generators from configured api values and memoizes proto_schema" do
          api = ::Object.new
          api.define_singleton_method(:proto_schema_package_name) { "sales.v1" }
          api.define_singleton_method(:proto_enums_by_graphql_enum) { {"Status" => {}} }
          api.define_singleton_method(:proto_field_number_mappings) { {"messages" => {"Account" => {"id" => 1}}} }
          api.define_singleton_method(:replace_json_schema_artifacts_with_proto?) { true }

          generator = instance_double(Schema, to_proto: "syntax = \"proto3\";", field_number_mappings_for_artifact: {"messages" => {}})

          results = build_results_with_api(api)

          expect(Schema).to receive(:new).with(
            results,
            package_name: "sales.v1",
            proto_enums_by_graphql_enum: {"Status" => {}},
            proto_field_number_mappings: {"messages" => {"Account" => {"id" => 1}}}
          ).and_return(generator)

          expect(results.proto_schema).to eq("syntax = \"proto3\";")
          expect(results.proto_schema).to eq("syntax = \"proto3\";")
          expect(results.proto_field_number_mappings).to eq({"messages" => {}})
          expect(results.replace_json_schema_artifacts_with_proto?).to eq(true)
        end

        it "falls back to defaults when api does not expose proto configuration methods" do
          api = ::Object.new
          generator = instance_double(Schema, to_proto: "", field_number_mappings_for_artifact: {"messages" => {}})
          results = build_results_with_api(api)

          expect(Schema).to receive(:new).with(
            results,
            package_name: "elasticgraph",
            proto_enums_by_graphql_enum: {},
            proto_field_number_mappings: {}
          ).and_return(generator)

          expect(results.proto_schema).to eq("")
          expect(results.replace_json_schema_artifacts_with_proto?).to eq(false)
        end
      end
    end
  end
end
