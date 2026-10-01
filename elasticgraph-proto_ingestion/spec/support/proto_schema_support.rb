# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/test_support"
require "elastic_graph/spec_support/protoc"
require "open3"
require "tempfile"

module ElasticGraph
  module ProtoIngestion
    module SchemaSupport
      include ElasticGraph::SchemaDefinition::TestSupport
      include SpecSupport::Protoc

      def envelope_field_number_mapping(record_name)
        {
          "fields" => {
            "op" => {"field_number" => 1, "proto_type" => "string", "list_depth" => 0},
            "id" => {"field_number" => 2, "proto_type" => "string", "list_depth" => 0},
            "version" => {"field_number" => 3, "proto_type" => "int64", "list_depth" => 0},
            "latency_timestamps" => {"field_number" => 4, "proto_type" => "map<string, google.protobuf.Timestamp>", "list_depth" => 1},
            record_name => {"field_number" => 5, "proto_type" => ".elasticgraph.#{Support::Casing.to_title(record_name)}", "list_depth" => 0}
          },
          "next_number" => 6
        }
      end

      def define_proto_schema(**options, &block)
        define_proto_schema_results(**options, &block).proto_schema
      end

      # Defines a schema, verifies its proto compiles, and returns its `Results`.
      # Pass the results of a previous
      # `define_proto_schema_results` call as `prior_results` to seed the new schema with the
      # field-number mappings the previous one generated, standing in for the
      # `proto_field_numbers.yaml` file that `schema_artifacts:dump` would have written between
      # the two schema definitions. (Loading that file is covered by
      # `schema_artifact_manager_extension_spec` and `rake_tasks_spec`.) `prior_results` is the
      # standard way to test mapping behavior; pass raw `proto_field_number_mappings:` only for
      # scenarios a prior dump cannot produce (such as a hand-edited or invalid file).
      def define_proto_schema_results(prior_results = nil, proto_field_number_mappings: nil, **options, &block)
        mappings = proto_field_number_mappings || prior_results&.proto_field_number_mappings

        results = define_schema(
          schema_element_name_form: :snake_case,
          extension_modules: [SchemaDefinition::APIExtension],
          **options
        ) do |schema|
          schema.state.proto_ingestion_state.field_number_mappings = mappings if mappings
          block.call(schema)
        end

        proto = results.proto_schema
        run_protoc(proto, "--descriptor_set_out=#{::File::NULL}", "") unless proto.empty?
        results
      end

      def run_protoc(proto_schema, operation, input)
        Tempfile.create(["schema", ".proto"]) do |schema_file|
          schema_file.write(proto_schema)
          schema_file.flush
          directory = ::File.dirname(schema_file.path)
          output, errors, status = Open3.capture3(
            PROTOC_BINARY,
            "--proto_path=#{directory}",
            "--proto_path=#{::File.expand_path("../fixtures/proto", __dir__)}",
            operation,
            ::File.basename(schema_file.path),
            stdin_data: input,
            binmode: true,
            chdir: directory
          )
          expect(status.success?).to be(true), errors
          output
        end
      end

      def proto_types_defined_in(proto)
        proto.scan(/^(?:enum|message) (\w+) \{/).flatten
      end

      def proto_type_def_from(proto, type)
        lines = proto.lines
        definition_start = /^(?:enum|message) #{Regexp.escape(type)} \{/
        definition_start_index = lines.index { |line| definition_start.match?(line) }
        return nil unless definition_start_index

        brace_depth = 0
        result_lines = lines.drop(definition_start_index).each_with_object([]) do |line, collected_lines|
          collected_lines << line
          structural_content = line.sub(%r{//.*}, "")
          brace_depth += structural_content.count("{") - structural_content.count("}")
          break collected_lines if brace_depth.zero?
        end

        result_lines.join.strip
      end
    end

    RSpec.configure do |config|
      config.include SchemaSupport, :proto_schema
    end
  end
end
