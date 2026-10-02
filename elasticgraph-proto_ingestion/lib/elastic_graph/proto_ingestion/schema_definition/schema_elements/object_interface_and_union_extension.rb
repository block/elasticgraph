# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/proto_ingestion/record_validator"
require "elastic_graph/proto_ingestion/runtime_schema"
require "elastic_graph/proto_ingestion/schema_definition/schema_elements/proto_documentation"
require "elastic_graph/schema_artifacts/runtime_metadata/scalar_type"
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
          def to_proto(schema, package_name)
            render_proto_message(schema, proto_name, package_name)
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
            @protobuf_contract&.fetch("proto_name", name) || name
          end

          # @return [Hash<String, Object>, nil] resolved historical message identity
          # @dynamic protobuf_contract, protobuf_contract=
          attr_accessor :protobuf_contract

          # Preserves this message's protobuf identity across a public GraphQL rename.
          # Available on unions as well as the object/interface types that expose it in core.
          # @param old_name [String]
          # @return [void]
          def renamed_from(old_name)
            schema_def_state.register_renamed_type(name, from: old_name, defined_at: caller_locations(1, 1).to_a.fetch(0), defined_via: %(type.renamed_from "#{old_name}"))
          end

          # Returns the fully qualified name used to reference this message from protobuf fields.
          #
          # @return [String]
          def proto_type_reference(package_name)
            ".#{package_name}.#{proto_name}"
          end

          # Messages render their own protobuf definition, so they never require an import.
          #
          # @return [nil]
          def protobuf_import
            nil
          end

          # Messages carry their documentation on the message definition itself, so fields of this
          # type get no format comment. Only scalar types document a format.
          #
          # @return [nil]
          def protobuf_field_comment
            nil
          end

          # Ingestion facts about this type's fields that its protobuf message cannot express: a private
          # `name_in_index`, and a scalar whose ingestion rules differ from those of its wire type's
          # default scalar. Kept out of the public wire schema.
          #
          # @return [Hash<String, Hash<String, String>>] overrides keyed by field name; fields without any are omitted
          def proto_field_overrides
            return {} if abstract?

            proto_fields.filter_map do |schema_field, field|
              overrides = {} # : ::Hash[::String, ::String]
              contract = schema_field.protobuf_contract # : FieldNumberMappings::contract
              wire_name = contract.fetch("proto_name", schema_field.name)
              overrides["public_name"] = schema_field.name unless wire_name == schema_field.name
              overrides["name_in_index"] = field.name_in_index unless field.name_in_index == schema_field.name

              base_type = ObjectInterfaceAndUnionExtension.list_depth_and_base_type(field.type).last.resolved
              if base_type.is_a?(::ElasticGraph::SchemaDefinition::SchemaElements::ScalarType)
                overrides.merge!(ObjectInterfaceAndUnionExtension.proto_scalar_overrides_for(_ = base_type, proto_type: contract.fetch("proto_type")))
              end

              [wire_name, overrides] unless overrides.empty?
            end.to_h
          end

          # Returns how a field of the given scalar type must name its scalar, or an empty hash when
          # ingesting it as its wire type's default scalar behaves the same. `string` scalars without
          # validation rules or an indexing preparer (`ID`, `Cursor`, most custom scalars) behave like `String`.
          #
          # @param scalar [ElasticGraph::SchemaDefinition::SchemaElements::ScalarType]
          # @return [Hash<String, String>]
          def self.proto_scalar_overrides_for(scalar, proto_type: scalar.proto_name)
            proto_type = proto_type.delete_prefix(".")
            return {} if scalar.name == RuntimeSchema::DEFAULT_SCALARS_BY_PROTO_TYPE[proto_type]

            scalar_name = scalar.type_ref.with_reverted_override.name
            plain_string = proto_type == "string" &&
              !RecordValidator::VALIDATED_SCALARS.include?(scalar_name) &&
              scalar.runtime_metadata.indexing_preparer_ref == SchemaArtifacts::RuntimeMetadata::ScalarType::DEFAULT_INDEXING_PREPARER_REF
            return {} if plain_string

            overrides = {"type" => scalar.name}
            overrides["scalar"] = scalar_name unless scalar_name == scalar.name
            overrides
          end

          # Indexing fields used to reconcile the message's historical wire contract.
          # @return [Array]
          def proto_fields
            @proto_fields ||= begin
              unless schema_def_state.user_definition_complete
                raise Errors::SchemaError, "Cannot access `proto_fields` until the schema definition is complete."
              end

              indexing_fields_by_name_in_index.values.filter_map do |raw_field|
                schema_field = raw_field # : ::ElasticGraph::SchemaDefinition::SchemaElements::Field & FieldExtension
                next if schema_field.name == "__typename"

                indexing_field = schema_field.to_indexing_field # : ElasticGraph::SchemaDefinition::Indexing::Field
                [schema_field, indexing_field] # : [::ElasticGraph::SchemaDefinition::SchemaElements::Field & FieldExtension, ::ElasticGraph::SchemaDefinition::Indexing::Field]
              end
            end
          end

          private

          def render_proto_message(schema, message_name, package_name)
            return render_proto_oneof(schema, message_name, package_name) if abstract?

            fields = proto_fields
            active_field_names = fields.map { |schema_field, _| schema_field.name }
            comments = [doc_comment, ("Public GraphQL type: #{name}." unless proto_name == name)].compact.join("\n")
            documentation = ProtoDocumentation.comment_lines_for(comments).map { |line| "#{line}\n" }.join
            field_definitions = fields.map do |schema_field, field|
              contract = schema_field.protobuf_contract # : FieldNumberMappings::contract
              repeated, field_type, field_comment = proto_field_type_for(
                field.type,
                package_name: package_name,
                context_field_name: contract.fetch("proto_name", schema_field.name),
                proto_base_type: contract.fetch("proto_type")
              )
              field_number = schema.field_number_for(
                message_name: message_name,
                type_name: name,
                public_field_name: schema_field.name
              )
              label = schema.field_label_prefix(repeated: repeated)
              wire_name = contract.fetch("proto_name", schema_field.name)
              line = "  #{label}#{field_type} #{wire_name} = #{field_number};"
              field_comments = [field_comment]
              field_comments << "Public GraphQL field: #{schema_field.name}." unless wire_name == schema_field.name
              if contract.fetch("proto_type") == "int64" && field.type.fully_unwrapped.name == "Int"
                field_comments << "Accepted range: -2147483648 to 2147483647. Values outside this range are rejected."
              end
              comment_lines = field_comment_lines_for(schema_field.doc_comment, field_comments.compact.join("\n").then { |comment| comment.empty? ? nil : comment })

              [*comment_lines, line].join("\n")
            end
            schema.reserved_field_numbers_for(message_name, active_field_names).each do |field_name, field_number|
              field_definitions << "  reserved #{field_number}; // Previously used by #{field_name}."
            end
            field_definitions << "  // Next field number: #{schema.next_field_number_for(message_name)}"

            body_sections = [field_definitions.join("\n"), *proto_list_wrapper_definitions(package_name)]
            <<~PROTO.chomp
              #{documentation}message #{message_name} {
              #{body_sections.join("\n\n")}
              }
            PROTO
          end

          def render_proto_oneof(schema, message_name, package_name)
            # @type var abstract_type: ::ElasticGraph::SchemaDefinition::Mixins::HasSubtypes
            abstract_type = _ = self
            comments = [doc_comment, ("Public GraphQL type: #{name}." unless proto_name == name)].compact.join("\n")
            documentation = ProtoDocumentation.comment_lines_for(comments).map { |line| "#{line}\n" }.join
            active_field_names = [] # : ::Array[::String]
            alternatives = abstract_type.recursively_resolve_subtypes.map do |subtype|
              proto_subtype = _ = subtype
              field_name = Support::Casing.to_upper_snake(proto_subtype.proto_name).downcase
              active_field_names << field_name
              field_number = schema.field_number_for(
                message_name: message_name,
                type_name: name,
                public_field_name: field_name
              )
              "    #{proto_subtype.proto_type_reference(package_name)} #{field_name} = #{field_number};"
            end
            body_lines = ["  oneof value {", *alternatives, "  }"]
            schema.reserved_field_numbers_for(message_name, active_field_names).each do |field_name, field_number|
              body_lines << "  reserved #{field_number}; // Previously used by #{field_name}."
            end
            body_lines << "  // Next field number: #{schema.next_field_number_for(message_name)}"

            <<~PROTO.chomp
              #{documentation}message #{message_name} {
              #{body_lines.join("\n")}
              }
            PROTO
          end

          # Renders a field's documentation and its type's format comment as the `//` lines that go
          # above the field. Proto compilers attach these leading comments to the code they generate
          # for the field, whereas a trailing comment on the field line is usually discarded.
          def field_comment_lines_for(doc_comment, field_comment)
            doc_lines = ProtoDocumentation.comment_lines_for(doc_comment, indent: "  ")
            return doc_lines unless field_comment

            format_lines = ProtoDocumentation.comment_lines_for(field_comment, indent: "  ")
            return format_lines if doc_lines.empty?

            doc_lines + ["  //"] + format_lines
          end

          def proto_list_wrapper_name(field_name, level, list_depth)
            suffix = (list_depth == 2) ? "" : level
            "#{Support::Casing.to_title(field_name)}List#{suffix}"
          end

          def proto_list_wrapper_definitions(package_name)
            proto_fields.flat_map do |schema_field, field|
              depth, = ObjectInterfaceAndUnionExtension.list_depth_and_base_type(field.type)
              contract = schema_field.protobuf_contract # : FieldNumberMappings::contract
              wire_name = contract.fetch("proto_name", schema_field.name)
              (1...depth).map do |level|
                element_type = if level == depth - 1
                  contract.fetch("proto_type")
                else
                  ".#{package_name}.#{proto_name}.#{proto_list_wrapper_name(wire_name, level + 1, depth)}"
                end
                [
                  "  message #{proto_list_wrapper_name(wire_name, level, depth)} {",
                  "    repeated #{element_type} values = 1;",
                  "  }"
                ].join("\n")
              end
            end
          end

          def proto_field_type_for(type_ref, package_name:, context_field_name:, proto_base_type:)
            list_depth, base_type_ref = ObjectInterfaceAndUnionExtension.list_depth_and_base_type(type_ref)

            proto_type = _ = base_type_ref.resolved
            field_type = if list_depth > 1
              ".#{package_name}.#{proto_name}.#{proto_list_wrapper_name(context_field_name, 1, list_depth)}"
            else
              proto_base_type
            end
            [list_depth >= 1, field_type, proto_type.protobuf_field_comment]
          end
        end
      end
    end
  end
end
