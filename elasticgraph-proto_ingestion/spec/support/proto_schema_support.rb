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

      def define_proto_schema_results(**options, &block)
        define_schema(
          schema_element_name_form: :snake_case,
          extension_modules: [SchemaDefinition::APIExtension],
          **options,
          &block
        )
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
