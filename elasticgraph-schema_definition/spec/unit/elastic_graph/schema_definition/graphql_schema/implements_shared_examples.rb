# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    RSpec.shared_examples_for "#implements" do |graphql_definition_keyword:, ruby_definition_method:|
      it "generates the correct `implements` syntax in the GraphQL SDL" do
        result = define_schema do |schema|
          schema.interface_type "HasID" do |t|
            t.field "id", "ID!"
          end

          schema.interface_type "HasName" do |t|
            t.field "name", "String"
          end

          schema.interface_type "HasColor" do |t|
            t.field "color", "String"
          end

          schema.public_send ruby_definition_method, "Thing" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "color", "String"

            t.implements "HasID", "HasName"
            t.implements "HasColor"
          end
        end

        expect(type_def_from(result, "Thing")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing implements HasID & HasName & HasColor {
            id: ID!
            name: String
            color: String
          }
        EOS
      end

      it "allows the `implements` call to come before the interface definition or the field implementations" do
        result = define_schema do |schema|
          schema.public_send ruby_definition_method, "Thing" do |t|
            t.implements "HasID"
            t.field "id", "ID!"
            t.field "name", "String"
          end

          schema.interface_type "HasID" do |t|
            t.field "id", "ID!"
          end
        end

        expect(type_def_from(result, "Thing")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing implements HasID {
            id: ID!
            name: String
          }
        EOS
      end

      it "raises a clear error when the type name is not formatted correctly" do
        expect {
          define_schema do |schema|
            schema.public_send(ruby_definition_method, "Invalid.Name") {}
          end
        }.to raise_invalid_graphql_name_error_for("Invalid.Name")
      end

      it "raises a clear error when the type name is not formatted correctly" do
        expect {
          define_schema do |schema|
            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "foo", "Invalid.Type!"
            end
          end
        }.to raise_invalid_graphql_name_error_for("Invalid.Type")
      end

      it "only allows wrapping characters ([]!) at their appropriate positions" do
        expect {
          define_schema do |schema|
            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "foo", "Invalid[Type!"
            end
          end
        }.to raise_invalid_graphql_name_error_for("Invalid[Type")

        expect {
          define_schema do |schema|
            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "foo", "Invalid]Type!"
            end
          end
        }.to raise_invalid_graphql_name_error_for("Invalid]Type")

        expect {
          define_schema do |schema|
            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "foo", "Invalid!Type!"
            end
          end
        }.to raise_invalid_graphql_name_error_for("Invalid!Type")
      end

      it "raises a clear error when the named type does not exist" do
        expect {
          define_schema do |schema|
            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "id", "ID!"
              t.implements "HasID"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Thing", "`HasID` is not defined")
      end

      it "raises a clear error when the named type is not an interface" do
        expect {
          define_schema do |schema|
            schema.enum_type "HasID" do |t|
              t.value "FOO"
            end

            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "id", "ID!"
              t.implements "HasID"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Thing", "`HasID` is not an interface")
      end

      it "raises a clear error when an object type does not implement one of the interface fields" do
        expect {
          define_schema do |schema|
            schema.interface_type "HasID" do |t|
              t.field "id", "ID!"
            end

            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "name", "String"
              t.field "color", "String"

              t.implements "HasID"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Thing", "HasID", "missing `id`")
      end

      it "raises a clear error when the object type implements one of the interface fields with the wrong type" do
        expect {
          define_schema do |schema|
            schema.interface_type "HasName" do |t|
              t.field "name", "String"
            end

            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "name", "Int"
              t.field "color", "String"

              t.implements "HasName"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Thing", "HasName", "`name: String` vs `name: Int`")
      end

      it "raises a clear error if the object and interface fields have different argument names" do
        expect {
          define_schema do |schema|
            schema.interface_type "HasName" do |t|
              t.field "name", "String" do |f|
                f.argument "truncate_at", "Int"
              end
            end

            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "name", "String" do |f|
                f.argument "truncate_after", "Int"
              end
              t.field "color", "String"

              t.implements "HasName"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Thing", "HasName", "`name(truncate_at: Int): String` vs `name(truncate_after: Int): String")
      end

      it "raises a clear error if the object and interface fields have different argument values" do
        expect {
          define_schema do |schema|
            schema.interface_type "HasName" do |t|
              t.field "name", "String" do |f|
                f.argument "truncate_at", "Int"
              end
            end

            schema.public_send ruby_definition_method, "Thing" do |t|
              t.field "name", "String" do |f|
                f.argument "truncate_at", "String"
              end
              t.field "color", "String"

              t.implements "HasName"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Thing", "HasName", "`name(truncate_at: Int): String` vs `name(truncate_at: String): String")
      end

      it "does not care if the interface and object fields have different documentation" do
        result = define_schema do |schema|
          schema.public_send ruby_definition_method, "Thing" do |t|
            t.implements "HasID"
            t.field "id", "ID!" do |f|
              f.documentation "Thing docs"
            end
            t.field "name", "String"
          end

          schema.interface_type "HasID" do |t|
            t.field "id", "ID!" do |f|
              f.documentation "HasID docs"
            end
          end
        end

        expect(type_def_from(result, "Thing")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing implements HasID {
            id: ID!
            name: String
          }
        EOS
      end

      it "does not care if the interface and object fields have different directives" do
        result = define_schema do |schema|
          schema.public_send ruby_definition_method, "Thing" do |t|
            t.implements "HasID"
            t.field "id", "ID!"
            t.field "name", "String"
          end

          schema.interface_type "HasID" do |t|
            t.field "id", "ID!" do |f|
              f.directive "deprecated"
            end
          end
        end

        expect(type_def_from(result, "Thing")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing implements HasID {
            id: ID!
            name: String
          }
        EOS
      end

      it "does not care if the interface and object fields have different JSON schema" do
        result = define_schema do |schema|
          schema.public_send ruby_definition_method, "Thing" do |t|
            t.implements "HasID"
            t.field "id", "ID!" do |f|
              f.json_schema maxLength: 40
            end
            t.field "name", "String"
          end

          schema.interface_type "HasID" do |t|
            t.field "id", "ID!" do |f|
              f.json_schema maxLength: 30
            end
          end
        end

        expect(type_def_from(result, "Thing")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing implements HasID {
            id: ID!
            name: String
          }
        EOS
      end

      it "does not care if the interface and object fields have different index mappings" do
        result = define_schema do |schema|
          schema.public_send ruby_definition_method, "Thing" do |t|
            t.implements "HasID"
            t.field "id", "ID!" do |f|
              f.mapping type: "text"
            end
            t.field "name", "String"
          end

          schema.interface_type "HasID" do |t|
            t.field "id", "ID!" do |f|
              f.mapping type: "keyword"
            end
          end
        end

        expect(type_def_from(result, "Thing")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing implements HasID {
            id: ID!
            name: String
          }
        EOS
      end

      it "does not care if the interface and object fields have different ElasticGraph abilities" do
        result = define_schema do |schema|
          schema.public_send ruby_definition_method, "Thing" do |t|
            t.implements "HasName"
            t.field "name", "String", sortable: false, groupable: false, filterable: false
          end

          schema.interface_type "HasName" do |t|
            t.field "name", "String", sortable: true, groupable: true, filterable: true
          end
        end

        expect(type_def_from(result, "Thing")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing implements HasName {
            name: String
          }
        EOS
      end

      it "does not care if one subtype has extra fields that another subtypes lacks" do
        result = define_schema do |schema|
          schema.public_send ruby_definition_method, "Thing1" do |t|
            t.implements "HasName"
            t.field "name", "String", sortable: false, groupable: false, filterable: false
            t.field "thing1", "Int"
          end

          schema.public_send ruby_definition_method, "Thing2" do |t|
            t.implements "HasName"
            t.field "name", "String", sortable: false, groupable: false, filterable: false
            t.field "thing2", "Int"
          end

          schema.interface_type "HasName" do |t|
            t.field "name", "String", sortable: true, groupable: true, filterable: true
          end
        end

        expect(type_def_from(result, "Thing1")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing1 implements HasName {
            name: String
            thing1: Int
          }
        EOS

        expect(type_def_from(result, "Thing2")).to eq(<<~EOS.strip)
          #{graphql_definition_keyword} Thing2 implements HasName {
            name: String
            thing2: Int
          }
        EOS
      end
    end
  end
end
