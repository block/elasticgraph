# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/api_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe Schema, :proto_schema do
        it "returns an empty string when no indexed types are present" do
          expect(build_schema_with_root_indexed_types.to_proto).to eq("")
        end

        it "supports the .generate convenience API" do
          results = define_proto_schema do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect(Schema.generate(results)).to eq(results.proto_schema)
        end

        it "raises when a root indexed type cannot be converted to proto" do
          bad_type = ::Object.new
          bad_type.define_singleton_method(:name) { "BadType" }

          schema = build_schema_with_root_indexed_types(bad_type)

          expect {
            schema.to_proto
          }.to raise_error(Errors::SchemaError, a_string_including("Type `BadType` cannot be converted to proto"))
        end

        it "uses inspect output for nameless types that cannot be converted" do
          bad_type = ::Object.new
          message = build_fake_message_type(
            "Account",
            "id" => build_fake_type_ref(resolved: build_fake_scalar_type("string"), unwrapped_name: "ID"),
            "broken" => build_fake_type_ref(resolved: bad_type, unwrapped_name: "Broken")
          )
          schema = build_schema_with_root_indexed_types(message)

          expect {
            schema.to_proto
          }.to raise_error(Errors::SchemaError, a_string_including(bad_type.inspect))
        end

        it "raises when a field type reference cannot be resolved" do
          message = build_fake_message_type(
            "BrokenMessage",
            "broken_field" => build_fake_type_ref(resolved: nil, unwrapped_name: "MissingType")
          )
          schema = build_schema_with_root_indexed_types(message)

          expect {
            schema.to_proto
          }.to raise_error(Errors::SchemaError, a_string_including("Type `MissingType` cannot be resolved"))
        end

        it "raises when enum values map to duplicate proto value names" do
          results = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.values "option", "OPTION"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("duplicate proto enum value names"))
        end

        it "uses a suffixed zero enum value when needed to avoid collisions" do
          results = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.values "UNSPECIFIED", "ACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          generated = proto_schema_from(results)
          expect(generated).to include("STATUS_UNSPECIFIED_ = 0;")
          expect(generated).to include("STATUS_UNSPECIFIED = 1;")
        end

        it "raises when a configured proto enum mapping source does not expose .enums" do
          results = define_proto_schema do |s|
            s.proto_enum_mappings("Status" => {::Object.new => {}})

            s.enum_type "Status" do |t|
              t.values "ACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must map to a proto enum class with `.enums`"))
        end

        it "wraps unexpected exceptions from enum mapping sources" do
          proto_status = ::Class.new do
            def self.enums
              [::Data.define(:name).new(name: :ACTIVE)]
            end
          end

          results = define_proto_schema do |s|
            s.proto_enum_mappings(
              "Status" => {
                proto_status => {
                  "name_transform" => ->(_name) { raise "boom" }
                }
              }
            )

            s.enum_type "Status" do |t|
              t.values "ACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("Failed loading proto enum mapping for `Status`"))
        end

        it "supports string-key mapping options in proto_enum_mappings" do
          proto_status = ::Class.new do
            def self.enums
              [
                ::Data.define(:name).new(name: :UNKNOWN_DO_NOT_USE),
                ::Data.define(:name).new(name: :ACTIVE)
              ]
            end
          end

          results = define_proto_schema do |s|
            s.proto_enum_mappings(
              "Status" => {
                proto_status => {
                  "exclusions" => [:UNKNOWN_DO_NOT_USE],
                  "expected_extras" => [:LEGACY]
                }
              }
            )

            s.enum_type "Status" do |t|
              t.values "ACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          generated = proto_schema_from(results)
          expect(generated).to include("STATUS_ACTIVE = 1;")
          expect(generated).to include("STATUS_LEGACY = 2;")
        end

        it "raises on field-number mapping collisions for a message" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {
                "messages" => {
                  "Account" => {
                    "id" => 1,
                    "name" => 1
                  }
                }
              }
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "name", "String"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("field-number mapping collision"))
        end

        it "raises when two fields collapse to the same proto field name after keyword escaping" do
          results = define_proto_schema do |s|
            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "string", "String"
              t.field "string_", "String"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("duplicate proto field names"))
        end

        it "generates unique nested-wrapper names when the base name is already taken" do
          results = define_proto_schema do |s|
            s.object_type "MatrixValuesListLevel1" do |t|
              t.field "id", "ID"
            end

            s.object_type "Matrix" do |t|
              t.field "id", "ID"
              t.field "already_taken", "MatrixValuesListLevel1"
              t.field "values", "[[Float!]!]!"
              t.index "matrices"
            end
          end

          generated = proto_schema_from(results)
          expect(generated).to include("message MatrixValuesListLevel12 {")
          expect(generated).to include("repeated MatrixValuesListLevel12 values = 3;")
        end

        it "renders a placeholder comment for indexed types with no fields" do
          schema = build_schema_with_root_indexed_types(build_fake_message_type("EmptyType"))
          expect(schema.to_proto).to include("// No indexed fields were defined for this type.")
        end

        it "supports recursive message references without infinite recursion" do
          node_type = build_fake_message_type(
            "Node",
            "id" => build_fake_type_ref(resolved: build_fake_scalar_type("string"), unwrapped_name: "ID"),
            "parent" => build_fake_type_ref(resolved: nil, unwrapped_name: "Node")
          )

          node_type
            .indexing_fields_by_name_in_index
            .fetch("parent")
            .to_indexing_field
            .type
            .define_singleton_method(:resolved) { node_type }

          schema = build_schema_with_root_indexed_types(node_type)

          expect(schema.to_proto).to include("Node parent = 2;")
        end

        it "supports re-registering already-known enums from field references" do
          status_enum = build_fake_enum_type("Status", values: ["ACTIVE"])
          account_type = build_fake_message_type(
            "Account",
            "status" => build_fake_type_ref(resolved: status_enum, unwrapped_name: "Status")
          )

          schema = build_schema_with_root_indexed_types(status_enum, account_type)
          expect(schema.to_proto).to include("STATUS_ACTIVE = 1;")
        end

        it "accepts multiple enum mapping sources when they resolve to the same values" do
          proto_status_a = ::Class.new do
            def self.enums
              [::Data.define(:name).new(name: :ACTIVE)]
            end
          end

          proto_status_b = ::Class.new do
            def self.enums
              [::Data.define(:name).new(name: :ACTIVE)]
            end
          end

          results = define_proto_schema do |s|
            s.proto_enum_mappings(
              "Status" => {
                proto_status_a => {},
                proto_status_b => {}
              }
            )

            s.enum_type "Status" do |t|
              t.values "ACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to include("STATUS_ACTIVE = 1;")
        end

        it "reuses nested wrapper types for repeated generation requests with the same context" do
          schema = build_schema_with_root_indexed_types

          first = schema.send(
            :register_nested_list_wrappers,
            context_message_name: "Matrix",
            context_field_name: "values",
            list_depth: 2,
            base_type_name: "double"
          )
          second = schema.send(
            :register_nested_list_wrappers,
            context_message_name: "Matrix",
            context_field_name: "values",
            list_depth: 2,
            base_type_name: "double"
          )

          expect(second).to eq(first)
        end

        it "creates intermediate wrappers for deeply nested lists" do
          results = define_proto_schema do |s|
            s.object_type "Matrix" do |t|
              t.field "id", "ID"
              t.field "values", "[[[Float!]!]!]!"
              t.index "matrices"
            end
          end

          generated = proto_schema_from(results)
          expect(generated).to include("message MatrixValuesListLevel2 {")
          expect(generated).to include("message MatrixValuesListLevel1 {")
        end

        it "normalizes nil proto enum and field-number mappings to empty hashes" do
          schema = Schema.new(
            build_fake_results_with_root_types,
            package_name: "elasticgraph",
            proto_enums_by_graphql_enum: nil,
            proto_field_number_mappings: nil
          )

          expect(schema.to_proto).to eq("")
          expect(schema.field_number_mappings_for_artifact).to eq({"messages" => {}})
        end

        it "raises when type names collide after proto message escaping" do
          first = build_fake_message_type("package")
          second = build_fake_message_type("package_")
          schema = build_schema_with_root_indexed_types(first, second)

          expect {
            schema.to_proto
          }.to raise_error(Errors::SchemaError, a_string_including("both map to the same proto message name"))
        end

        it "raises when type names collide after proto enum escaping" do
          first = build_fake_enum_type("option", values: ["ACTIVE"])
          second = build_fake_enum_type("option_", values: ["ACTIVE"])
          schema = build_schema_with_root_indexed_types(first, second)

          expect {
            schema.to_proto
          }.to raise_error(Errors::SchemaError, a_string_including("both map to the same proto enum name"))
        end

        it "validates field-number mapping input type" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings("bad")

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must be a Hash"))
        end

        it "validates that `messages` is a hash in field-number mappings" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings({"messages" => "bad"})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must have a `messages` Hash"))
        end

        it "accepts symbol `:messages` key in field-number mappings" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {
                messages: {
                  "Account" => {
                    "id" => 7
                  }
                }
              }
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to include("string id = 7;")
        end

        it "accepts symbol `:fields` and nested symbol keys in field-number mappings" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {
                messages: {
                  "Account" => {
                    fields: {
                      "id" => {
                        field_number: 7,
                        name_in_index: :account_id
                      }
                    }
                  }
                }
              }
            )

            s.object_type "Account" do |t|
              t.field "id", "ID", name_in_index: "account_id"
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to include("string id = 7;")
        end

        it "validates per-message field-number mapping structure" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => "bad"}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must be a Hash"))
        end

        it "validates that nested `fields` is a hash in field-number mappings" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => {"fields" => "bad"}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must contain a `fields` Hash"))
        end

        it "validates that mapped field numbers are positive integers" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => {"id" => 0}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer"))
        end

        it "validates that mapped field numbers are integers" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings({"messages" => {"Account" => {"id" => "abc"}}})

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must be an integer"))
        end

        it "validates that structured mappings include `field_number`" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"id" => {"name_in_index" => "account_id"}}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID", name_in_index: "account_id"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must include `field_number`"))
        end

        it "validates that structured mappings use a String or Symbol `name_in_index`" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"id" => {"field_number" => 7, "name_in_index" => 123}}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.index "accounts"
            end
          end

          expect {
            proto_schema_from(results)
          }.to raise_error(Errors::SchemaError, a_string_including("must use a String or Symbol `name_in_index`"))
        end

        it "defaults structured mappings without `name_in_index` to the field name" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"display_name" => {"field_number" => 7}}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "display_name", "String"
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to include("string display_name = 7;")
        end

        it "allocates the next available field number when a renamed field has no old mapping entry" do
          results = define_proto_schema do |s|
            s.configure_proto_field_number_mappings(
              {"messages" => {"Account" => {"fields" => {"other_name" => 7}}}}
            )

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "display_name", "String" do |f|
                f.renamed_from "full_name"
              end
              t.index "accounts"
            end
          end

          expect(proto_schema_from(results)).to include("string id = 1;")
          expect(proto_schema_from(results)).to include("string display_name = 2;")
        end

        private

        def build_schema_with_root_indexed_types(*indexed_types)
          fake_results = build_fake_results_with_root_types(*indexed_types)

          Schema.new(
            fake_results,
            package_name: "elasticgraph",
            proto_enums_by_graphql_enum: {},
            proto_field_number_mappings: {}
          )
        end

        def build_fake_results_with_root_types(*indexed_types)
          wrappers = indexed_types.map do |indexed_type|
            ::Object.new.tap do |wrapper|
              wrapper.define_singleton_method(:index_def) do
                ::Struct.new(:indexed_type).new(indexed_type)
              end
            end
          end

          fake_results = ::Object.new
          fake_results.define_singleton_method(:schema_artifact_types) { wrappers }
          fake_results
        end

        def build_fake_scalar_type(proto_type_name)
          scalar = ::Object.new
          scalar.define_singleton_method(:to_proto_field_type) { proto_type_name }
          scalar
        end

        def build_fake_type_ref(resolved:, unwrapped_name:)
          ref = ::Object.new
          ref.define_singleton_method(:unwrap_non_null) { ref }
          ref.define_singleton_method(:list?) { false }
          ref.define_singleton_method(:resolved) { resolved }
          ref.define_singleton_method(:unwrapped_name) { unwrapped_name }
          ref
        end

        def build_fake_message_type(name, fields_by_name = {})
          type = ::Object.new
          type.define_singleton_method(:name) { name }
          type.define_singleton_method(:to_proto_field_type) { Identifier.message_name(name) }
          type.define_singleton_method(:indexing_fields_by_name_in_index) do
            fields_by_name.each_with_object({}) do |(field_name, type_ref), transformed|
              indexing_field = ::Struct.new(:name, :name_in_index, :type).new(field_name, field_name, type_ref)
              transformed[field_name] = ::Struct.new(:to_indexing_field).new(indexing_field)
            end
          end
          type
        end

        def build_fake_enum_type(name, values:)
          type = ::Object.new
          type.define_singleton_method(:name) { name }
          type.define_singleton_method(:to_proto_field_type) { Identifier.enum_name(name) }
          type.define_singleton_method(:values_by_name) { values.to_h { |v| [v, true] } }
          type
        end
      end
    end
  end
end
