# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module ProtoIngestion
    module SchemaSupport
      include ElasticGraph::SchemaDefinition::TestSupport

      def define_proto_schema(**options, &block)
        define_proto_schema_results(**options, &block).proto_schema
      end

      # Defines a schema and returns its `Results`. Pass the results of a previous
      # `define_proto_schema_results` call as `prior_results` to seed the new schema with the
      # field-number mappings the previous one dumped, mirroring how `schema_artifacts:dump`
      # loads the `proto_field_numbers.yaml` artifact from the prior dump. That is the standard
      # way to test mapping behavior; pass raw `proto_field_number_mappings:` only for scenarios
      # a prior dump cannot produce (such as a hand-edited or invalid artifact).
      def define_proto_schema_results(prior_results = nil, proto_field_number_mappings: nil, **options, &block)
        mappings = proto_field_number_mappings || prior_results&.proto_field_number_mappings

        define_schema(
          schema_element_name_form: :snake_case,
          extension_modules: [SchemaDefinition::APIExtension],
          **options
        ) do |schema|
          schema.state.proto_ingestion_state.field_number_mappings = mappings if mappings
          block.call(schema)
        end
      end

      def proto_type_def_from(proto, type)
        lines = proto.lines
        definition_start = /^(?:enum|message) #{Regexp.escape(type)} \{/
        start_indices = lines.each_index.select { |index| definition_start.match?(lines.fetch(index)) }

        if start_indices.size >= 2
          # :nocov: -- only executed when a mistake has been made; causes a failing test.
          raise Errors::SchemaError,
            "Expected to find 0 or 1 proto type definition for #{type}, but found #{start_indices.size}."
          # :nocov:
        end

        definition_start_index = start_indices.first
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
