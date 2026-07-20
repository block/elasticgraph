# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
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
          def to_proto(package_name)
            render_proto_message(proto_name, package_name)
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

          # Returns a type reference's list depth and fully unwrapped base type.
          #
          # @return [Array]
          def self.list_depth_and_base_type(type_ref)
            list_depth = 0
            current = type_ref.unwrap_non_null

            while current.list?
              list_depth += 1
              current = current.unwrap_list.unwrap_non_null
            end

            [list_depth, current]
          end

          # Returns this type's name in protobuf schemas.
          #
          # @return [String]
          def proto_name
            name
          end

          # Returns the fully qualified name used to reference this message from protobuf fields.
          #
          # @return [String]
          def proto_type_reference(package_name)
            ".#{package_name}.#{proto_name}"
          end

          private

          def render_proto_message(message_name, package_name)
            return render_proto_oneof(message_name, package_name) if abstract?

            fields = proto_fields
            documentation = ProtoDocumentation.comment_lines_for(doc_comment).map { |line| "#{line}\n" }.join
            field_definitions = fields.each.with_index(1).map do |(schema_field, field), field_number|
              repeated, field_type = proto_field_type_for(
                field.type,
                package_name: package_name,
                context_field_name: field.name
              )
              label = "repeated " if repeated
              line = "  #{label}#{field_type} #{field.name} = #{field_number};"
              field_documentation = ProtoDocumentation
                .comment_lines_for(schema_field.doc_comment, indent: "  ")
                .map { |comment_line| "#{comment_line}\n" }
                .join

              "#{field_documentation}#{line}"
            end

            <<~PROTO.chomp
              #{documentation}message #{message_name} {
              #{field_definitions.join("\n")}
              }
            PROTO
          end

          def render_proto_oneof(message_name, package_name)
            # @type var abstract_type: ::ElasticGraph::SchemaDefinition::Mixins::HasSubtypes
            abstract_type = _ = self
            documentation = ProtoDocumentation.comment_lines_for(doc_comment).map { |line| "#{line}\n" }.join
            alternatives = abstract_type.recursively_resolve_subtypes.each.with_index(1).map do |subtype, field_number|
              proto_subtype = _ = subtype
              field_name = Support::Casing.to_upper_snake(proto_subtype.proto_name).downcase
              "    #{proto_subtype.proto_type_reference(package_name)} #{field_name} = #{field_number};"
            end

            <<~PROTO.chomp
              #{documentation}message #{message_name} {
                oneof value {
              #{alternatives.join("\n")}
                }
              }
            PROTO
          end

          def proto_fields
            @proto_fields ||= begin
              unless schema_def_state.user_definition_complete
                raise Errors::SchemaError, "Cannot access `proto_fields` until the schema definition is complete."
              end

              indexing_fields_by_name_in_index.values.filter_map do |schema_field|
                next if schema_field.name == "__typename"

                indexing_field = schema_field.to_indexing_field # : ElasticGraph::SchemaDefinition::Indexing::Field
                [schema_field, indexing_field] # : [::ElasticGraph::SchemaDefinition::SchemaElements::Field, ::ElasticGraph::SchemaDefinition::Indexing::Field]
              end
            end
          end

          def proto_field_type_for(type_ref, package_name:, context_field_name:)
            list_depth, base_type_ref = ObjectInterfaceAndUnionExtension.list_depth_and_base_type(type_ref)

            if list_depth > 1
              raise Errors::SchemaError, "Field `#{name}.#{context_field_name}` has type `#{type_ref.name}`, " \
                "but Protocol Buffers cannot represent lists of lists directly. " \
                "`elasticgraph-proto_ingestion` supports fields with at most one list level."
            end

            proto_type = _ = base_type_ref.resolved
            [list_depth == 1, proto_type.proto_type_reference(package_name)]
          end
        end
      end
    end
  end
end
