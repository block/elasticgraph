# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/schema_definition/identifier"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/proto_documentation"
require "elastic_graph/support/casing"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      module SchemaElements
        # Extends object/interface/union types with proto field type conversion.
        module ObjectInterfaceAndUnionExtension
          # Renders this type's protobuf message definition.
          #
          # @return [String]
          def to_proto(schema)
            render_proto_message(schema, proto_name)
          end

          # Returns the kind used to order this definition in a protobuf schema.
          #
          # @return [Symbol]
          def proto_definition_kind
            :message
          end

          # Returns the schema types referenced by this definition.
          #
          # @return [Array]
          def referenced_proto_types
            if abstract?
              abstract_type = _ = self
              abstract_type.recursively_resolve_subtypes
            else
              proto_fields.map do |_, field|
                _ = field.type.fully_unwrapped.resolved
              end
            end
          end

          # Returns this type's name in protobuf schemas.
          #
          # @return [String]
          def proto_name
            @proto_name ||= Identifier.message_name(name)
          end

          private

          def render_proto_message(schema, message_name)
            return render_proto_oneof(schema, message_name) if abstract?

            fields = proto_fields
            field_names = fields.map { |_, field| Identifier.field_name(field.name) }
            duplicate_names = field_names.tally.select { |_, count| count > 1 }
            if duplicate_names.any?
              raise Errors::SchemaError, "Type `#{name}` maps to duplicate proto field names: #{duplicate_names.keys.sort.join(", ")}."
            end

            lines = ProtoDocumentation.comment_lines_for(doc_comment)
            lines << "message #{message_name} {"
            fields.each do |schema_field, field|
              field_name = Identifier.field_name(field.name)
              repeated, field_type = proto_field_type_for(field.type, context_field_name: field.name)
              field_number = schema.field_number_for(
                message_name: message_name,
                type_name: name,
                public_field_name: schema_field.name,
                name_in_index: field.name_in_index
              )
              label = "repeated " if repeated
              line = "  #{label}#{field_type} #{field_name} = #{field_number};"
              line += " // source name: #{field.name}" if field_name != field.name
              lines.concat(ProtoDocumentation.comment_lines_for(schema_field.doc_comment, indent: "  "))
              lines << line
            end
            lines << "}"
            lines.join("\n")
          end

          def render_proto_oneof(schema, message_name)
            # @type var abstract_type: ::ElasticGraph::SchemaDefinition::Mixins::HasSubtypes
            abstract_type = _ = self
            lines = ProtoDocumentation.comment_lines_for(doc_comment)
            lines << "message #{message_name} {"
            lines << "  oneof value {"
            abstract_type.recursively_resolve_subtypes.each do |subtype|
              subtype_name = (_ = subtype).proto_name
              field_name = Identifier.field_name(Support::Casing.to_upper_snake(subtype_name).downcase)
              field_number = schema.field_number_for(
                message_name: message_name,
                type_name: name,
                public_field_name: field_name,
                name_in_index: field_name
              )
              lines << "    #{subtype_name} #{field_name} = #{field_number};"
            end
            lines << "  }"
            lines << "}"
            lines.join("\n")
          end

          def proto_fields
            indexing_fields_by_name_in_index.values.filter_map do |schema_field|
              next if schema_field.name == "__typename"

              indexing_field = schema_field.to_indexing_field # : ElasticGraph::SchemaDefinition::Indexing::Field
              [schema_field, indexing_field] # : [::ElasticGraph::SchemaDefinition::SchemaElements::Field, ::ElasticGraph::SchemaDefinition::Indexing::Field]
            end
          end

          def proto_field_type_for(type_ref, context_field_name:)
            list_depth, base_type_ref = list_depth_and_base_type(type_ref)

            if list_depth > 1
              raise Errors::SchemaError, "Field `#{name}.#{context_field_name}` has type `#{type_ref.name}`, " \
                "but Protocol Buffers cannot represent lists of lists directly. " \
                "`elasticgraph-proto_ingestion` supports fields with at most one list level."
            end

            proto_type = _ = base_type_ref.resolved
            [list_depth == 1, proto_type.proto_name]
          end

          def list_depth_and_base_type(type_ref)
            list_depth = 0
            current = type_ref.unwrap_non_null

            while current.list?
              list_depth += 1
              current = current.unwrap_list.unwrap_non_null
            end

            [list_depth, current]
          end
        end
      end
    end
  end
end
