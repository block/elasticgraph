# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"

module ElasticGraph
  module SchemaDefinition
    # Prunes unused type definitions from a given JSON schema.
    #
    # @private
    class JSONSchemaPruner
      def self.prune(original_json_schema)
        initial_type_names = [EVENT_ENVELOPE_JSON_SCHEMA_NAME] + original_json_schema
          .dig("$defs", EVENT_ENVELOPE_JSON_SCHEMA_NAME, "properties", "type", "enum")

        types_to_keep = referenced_type_names(initial_type_names, original_json_schema["$defs"])

        # The .select will preserve the sort order of the original hash
        # standard:disable Style/HashSlice -- https://github.com/soutaro/steep/issues/1503
        pruned_defs = original_json_schema["$defs"].select { |k, _v| types_to_keep.include?(k) }
        # standard:enable Style/HashSlice

        original_json_schema.merge("$defs" => pruned_defs)
      end

      # Returns a list of type names indicating all types referenced from any type in source_type_names.
      private_class_method
      def self.referenced_type_names(source_type_names, original_defs)
        return Set.new if source_type_names.empty?

        referenced_type_defs = original_defs.slice(*source_type_names)
        ref_names = collect_ref_names(referenced_type_defs)

        referenced_type_names(ref_names, original_defs) + source_type_names
      end

      private_class_method
      def self.collect_ref_names(hash)
        hash.flat_map do |key, value|
          case value
          when ::Hash
            collect_ref_names(value)
          when ::Array
            value.grep(::Hash).flat_map { |subhash| collect_ref_names(subhash) }
          when ::String
            if key == "$ref" && (type = value[%r{\A#/\$defs/(.+)\z}, 1])
              [type]
            else
              []
            end
          else
            []
          end
        end
      end
    end
  end
end
