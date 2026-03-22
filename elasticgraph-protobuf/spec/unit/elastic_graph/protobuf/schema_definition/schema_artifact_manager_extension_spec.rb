# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/schema_artifact_manager_extension"
require "tmpdir"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe SchemaArtifactManagerExtension do
        def build_manager(results)
          stateful_base = ::Class.new do
            attr_reader :schema_definition_results

            def initialize(schema_definition_results)
              @schema_definition_results = schema_definition_results
              @schema_artifacts_directory = ::Dir.pwd
            end

            private

            def artifacts_from_schema_def
              [:base_artifact]
            end
          end

          ::Class.new(stateful_base) do
            prepend SchemaArtifactManagerExtension
          end.new(results)
        end

        it "returns base artifacts when api cannot configure proto field-number mappings" do
          api = ::Object.new
          state = ::Struct.new(:api).new(api)
          results = ::Object.new
          results.define_singleton_method(:state) { state }

          manager = build_manager(results)

          expect(manager.send(:artifacts_from_schema_def)).to eq([:base_artifact])
        end

        it "loads mappings from file and forwards them to api configuration" do
          configured = false

          mapping_dir = ::Dir.mktmpdir
          mapping_file = ::File.join(mapping_dir, Protobuf::PROTO_FIELD_NUMBERS_FILE)
          ::File.write(mapping_file, <<~YAML)
            ---
            messages:
              Account:
                id: 1
          YAML

          api = ::Object.new
          api.define_singleton_method(:configure_proto_field_number_mappings) do |mappings, enforce: false|
            configured = (mappings == {"messages" => {"Account" => {"id" => 1}}})
          end

          state = ::Struct.new(:api).new(api)
          results = ::Object.new
          results.define_singleton_method(:state) { state }

          manager = build_manager(results)
          manager.instance_variable_set(:@schema_artifacts_directory, mapping_dir)

          expect(manager.send(:artifacts_from_schema_def)).to eq([:base_artifact])
          expect(configured).to eq(true)
        end
      end
    end
  end
end
