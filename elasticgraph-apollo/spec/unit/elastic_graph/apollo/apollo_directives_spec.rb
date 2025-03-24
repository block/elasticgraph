# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/api_extension"
require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module Apollo
    RSpec.describe SchemaDefinition do
      include_context "SchemaDefinitionHelpers"

      def self.with_both_casing_forms(&block)
        context "with schema elements configured to use camelCase" do
          let(:schema_element_name_form) { :camelCase }
          module_exec(&block)
        end

        context "with schema elements configured to use snake_case" do
          let(:schema_element_name_form) { :snake_case }
          module_exec(&block)
        end
      end

      with_both_casing_forms do
        let(:schema_elements) { SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: schema_element_name_form) }

        it "adds an `@authenticated` directive when `apollo_authenticated` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.enum_type "Size" do |e|
              e.apollo_authenticated
              e.value "SMALL"
            end

            schema.interface_type "Identifiable" do |t|
              t.apollo_authenticated
              t.field "size", "Size"
            end

            schema.object_type "Widget" do |t|
              t.implements "Identifiable"
              t.apollo_authenticated

              t.field "name", "String" do |f|
                f.apollo_authenticated
              end

              t.field "size", "Size"
              t.field "url", "Url"
            end

            schema.scalar_type "Url" do |f|
              f.apollo_authenticated
              f.mapping type: "keyword"
              f.json_schema type: "string"
            end
          end

          expect(type_def_from(schema_string, "Size")).to eq(<<~EOS.strip)
            enum Size @authenticated {
              SMALL
            }
          EOS

          expect(type_def_from(schema_string, "Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable @authenticated {
              size: Size
            }
          EOS

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @authenticated {
              name: String @authenticated
              size: Size
              url: Url
            }
          EOS

          expect(type_def_from(schema_string, "Url")).to eq(<<~EOS.strip)
            scalar Url @authenticated
          EOS
        end

        it "adds an `@extends` directive when `apollo_extends` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.interface_type "Identifiable" do |t|
              t.apollo_extends
              t.field "name", "String"
            end

            schema.object_type "Widget" do |t|
              t.implements "Identifiable"

              t.apollo_extends
              t.field "name", "String"
            end
          end

          expect(type_def_from(schema_string, "Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable @extends {
              name: String
            }
          EOS

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @extends {
              name: String
            }
          EOS
        end

        it "adds an `@external` directive when `apollo_external` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "Widget" do |t|
              t.apollo_external

              t.field "name", "String" do |f|
                f.apollo_external
              end
            end
          end

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget @external {
              name: String @external
            }
          EOS
        end

        it "adds an `@inaccessible` directive when `apollo_inaccessible` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.enum_type "Size" do |e|
              e.apollo_inaccessible

              e.value "SMALL" do |v|
                v.apollo_inaccessible
              end
            end

            schema.interface_type "Identifiable" do |t|
              t.apollo_inaccessible
              t.field "size", "Size"
            end

            schema.object_type "Widget" do |t|
              t.implements "Identifiable"

              t.apollo_inaccessible

              t.field "name", "String" do |f|
                f.apollo_inaccessible

                f.argument "some_arg", "String" do |a|
                  a.apollo_inaccessible
                end
              end

              t.field "size", "Size"
              t.field "url", "Url"
            end

            schema.scalar_type "Url" do |f|
              f.apollo_inaccessible
              f.mapping type: "keyword"
              f.json_schema type: "string"

              f.customize_derived_types "UrlFilterInput" do |dt|
                dt.apollo_inaccessible
                dt.field "host", "String" do |dtf|
                  dtf.apollo_inaccessible
                end
              end
            end

            schema.union_type "Thing" do |t|
              t.apollo_inaccessible
              t.subtype "Widget"
            end
          end

          expect(type_def_from(schema_string, "Size")).to eq(<<~EOS.strip)
            enum Size @inaccessible {
              SMALL @inaccessible
            }
          EOS

          expect(type_def_from(schema_string, "Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable @inaccessible {
              size: Size
            }
          EOS

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @inaccessible {
              name(
                some_arg: String @inaccessible): String @inaccessible
              size: Size
              url: Url
            }
          EOS

          expect(type_def_from(schema_string, "Thing")).to eq(<<~EOS.strip)
            union Thing @inaccessible = Widget
          EOS

          expect(type_def_from(schema_string, "Url")).to eq(<<~EOS.strip)
            scalar Url @inaccessible
          EOS

          expect(type_def_from(schema_string, "UrlFilterInput")).to eq(<<~EOS.strip)
            input UrlFilterInput @inaccessible {
              #{schema_elements.any_of}: [UrlFilterInput!]
              #{schema_elements.all_of}: [UrlFilterInput!]
              #{schema_elements.not}: UrlFilterInput
              #{schema_elements.equal_to_any_of}: [Url]
              host: String @inaccessible
            }
          EOS
        end

        it "adds an `@interfaceObject` directive when `apollo_interface_object` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "Widget" do |t|
              t.apollo_interface_object
              t.field "name", "String"
            end
          end

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget @interfaceObject {
              name: String
            }
          EOS
        end

        it "adds a `@key` directive when `apollo_key` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.interface_type "Identifiable" do |t|
              t.apollo_key(fields: "age")
              t.field "age", "Int"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.implements "Identifiable"

              t.apollo_key(fields: "first_name last_name")
              t.apollo_key(fields: "address", resolvable: false)

              t.field "first_name", "String"
              t.field "last_name", "String"
              t.field "address", "String"
              t.field "age", "Int"
              t.index "widgets"
            end
          end

          expect(type_def_from(schema_string, "Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable @key(fields: "age", resolvable: true) {
              age: Int
            }
          EOS

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @key(fields: "first_name last_name", resolvable: true) @key(fields: "address", resolvable: false) @key(fields: "id", resolvable: true) {
              id: ID!
              first_name: String
              last_name: String
              address: String
              age: Int
            }
          EOS
        end

        it "adds an `@override` directive when `apollo_override` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "Widget" do |t|
              t.field "name", "String" do |f|
                f.apollo_override(from: "AnotherGraph")
              end
            end
          end

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget {
              name: String @override(from: "AnotherGraph")
            }
          EOS
        end

        it "adds a `@policy` directive when `apollo_policy` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.enum_type "Size" do |e|
              e.apollo_policy(policies: [["Policy1", "Policy2"], ["Policy3"]])
              e.value "SMALL"
            end

            schema.interface_type "Identifiable" do |t|
              t.apollo_policy(policies: [["Policy1", "Policy2"], ["Policy3"]])
              t.field "size", "Size"
            end

            schema.object_type "Widget" do |t|
              t.implements "Identifiable"
              t.apollo_policy(policies: [["Policy1", "Policy2"], ["Policy3"]])

              t.field "name", "String" do |f|
                f.apollo_policy(policies: [["Policy1", "Policy2"], ["Policy3"]])
              end

              t.field "size", "Size"
              t.field "url", "Url"
            end

            schema.scalar_type "Url" do |f|
              f.apollo_policy(policies: [["Policy1", "Policy2"], ["Policy3"]])
              f.mapping type: "keyword"
              f.json_schema type: "string"
            end
          end

          expect(type_def_from(schema_string, "Size")).to eq(<<~EOS.strip)
            enum Size @policy(policies: [["Policy1", "Policy2"], ["Policy3"]]) {
              SMALL
            }
          EOS

          expect(type_def_from(schema_string, "Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable @policy(policies: [["Policy1", "Policy2"], ["Policy3"]]) {
              size: Size
            }
          EOS

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @policy(policies: [["Policy1", "Policy2"], ["Policy3"]]) {
              name: String @policy(policies: [["Policy1", "Policy2"], ["Policy3"]])
              size: Size
              url: Url
            }
          EOS

          expect(type_def_from(schema_string, "Url")).to eq(<<~EOS.strip)
            scalar Url @policy(policies: [["Policy1", "Policy2"], ["Policy3"]])
          EOS
        end

        it "adds a `@provides` directive when `apollo_provides` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "Widget" do |t|
              t.field "name", "String" do |f|
                f.apollo_provides(fields: "name")
              end
            end
          end

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget {
              name: String @provides(fields: "name")
            }
          EOS
        end

        it "adds a `@requires` directive when `apollo_requires` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "Widget" do |t|
              t.field "name", "String" do |f|
                f.apollo_requires(fields: "name")
              end
            end
          end

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget {
              name: String @requires(fields: "name")
            }
          EOS
        end

        it "adds a `@requiresScopes` directive when `apollo_requires_scopes` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.enum_type "Size" do |e|
              e.apollo_requires_scopes(scopes: [["Scope1", "Scope2"], ["Scope3"]])
              e.value "SMALL"
            end

            schema.interface_type "Identifiable" do |t|
              t.apollo_requires_scopes(scopes: [["Scope1", "Scope2"], ["Scope3"]])
              t.field "size", "Size"
            end

            schema.object_type "Widget" do |t|
              t.implements "Identifiable"
              t.apollo_requires_scopes(scopes: [["Scope1", "Scope2"], ["Scope3"]])

              t.field "name", "String" do |f|
                f.apollo_requires_scopes(scopes: [["Scope1", "Scope2"], ["Scope3"]])
              end

              t.field "size", "Size"
              t.field "url", "Url"
            end

            schema.scalar_type "Url" do |f|
              f.apollo_requires_scopes(scopes: [["Scope1", "Scope2"], ["Scope3"]])
              f.mapping type: "keyword"
              f.json_schema type: "string"
            end
          end

          expect(type_def_from(schema_string, "Size")).to eq(<<~EOS.strip)
            enum Size @requiresScopes(scopes: [["Scope1", "Scope2"], ["Scope3"]]) {
              SMALL
            }
          EOS

          expect(type_def_from(schema_string, "Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable @requiresScopes(scopes: [["Scope1", "Scope2"], ["Scope3"]]) {
              size: Size
            }
          EOS

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @requiresScopes(scopes: [["Scope1", "Scope2"], ["Scope3"]]) {
              name: String @requiresScopes(scopes: [["Scope1", "Scope2"], ["Scope3"]])
              size: Size
              url: Url
            }
          EOS

          expect(type_def_from(schema_string, "Url")).to eq(<<~EOS.strip)
            scalar Url @requiresScopes(scopes: [["Scope1", "Scope2"], ["Scope3"]])
          EOS
        end

        it "adds a `@shareable` directive when `apollo_shareable` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.object_type "Widget" do |t|
              t.apollo_shareable

              t.field "name", "String" do |f|
                f.apollo_shareable
              end
            end
          end

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget @shareable {
              name: String @shareable
            }
          EOS
        end

        it "adds a `@tag` directive when `apollo_tag` is called on a schema element" do
          schema_string = graphql_schema_string do |schema|
            schema.enum_type "Size" do |e|
              e.apollo_tag name: "test"

              e.value "SMALL" do |v|
                v.apollo_tag name: "test"
              end

              e.value "MEDIUM"
            end

            schema.interface_type "Identifiable" do |t|
              t.apollo_tag name: "test"
              t.field "size", "Size"
            end

            schema.object_type "Widget" do |t|
              t.implements "Identifiable"

              t.apollo_tag name: "test"

              t.field "name", "String" do |f|
                f.apollo_tag name: "test"

                f.argument "some_arg", "String" do |a|
                  a.apollo_tag name: "test"
                end

                f.argument "empty_argument", "String"
              end

              t.field "size", "Size"
              t.field "url", "Url"
            end

            schema.scalar_type "Url" do |f|
              f.apollo_tag name: "test"
              f.mapping type: "keyword"
              f.json_schema type: "string"

              f.customize_derived_types "UrlFilterInput" do |dt|
                dt.apollo_tag name: "test"
                dt.field "host", "String" do |dtf|
                  dtf.apollo_tag name: "test"
                end
              end
            end

            schema.union_type "Thing" do |t|
              t.apollo_tag name: "test"
              t.subtype "Widget"
            end
          end

          expect(type_def_from(schema_string, "Size")).to eq(<<~EOS.strip)
            enum Size @tag(name: "test") {
              SMALL @tag(name: "test")
              MEDIUM
            }
          EOS

          expect(type_def_from(schema_string, "Identifiable")).to eq(<<~EOS.strip)
            interface Identifiable @tag(name: "test") {
              size: Size
            }
          EOS

          expect(type_def_from(schema_string, "Widget")).to eq(<<~EOS.strip)
            type Widget implements Identifiable @tag(name: "test") {
              name(
                some_arg: String @tag(name: "test")
                empty_argument: String): String @tag(name: "test")
              size: Size
              url: Url
            }
          EOS

          expect(type_def_from(schema_string, "Thing")).to eq(<<~EOS.strip)
            union Thing @tag(name: "test") = Widget
          EOS

          expect(type_def_from(schema_string, "Url")).to eq(<<~EOS.strip)
            scalar Url @tag(name: "test")
          EOS

          expect(type_def_from(schema_string, "UrlFilterInput")).to eq(<<~EOS.strip)
            input UrlFilterInput @tag(name: "test") {
              #{schema_elements.any_of}: [UrlFilterInput!]
              #{schema_elements.all_of}: [UrlFilterInput!]
              #{schema_elements.not}: UrlFilterInput
              #{schema_elements.equal_to_any_of}: [Url]
              host: String @tag(name: "test")
            }
          EOS
        end

        def define_schema(&block)
          extension_modules = [SchemaDefinition::APIExtension]
          super(schema_element_name_form: schema_element_name_form, extension_modules: extension_modules, &block)
        end
      end

      def graphql_schema_string(&block)
        schema = define_schema(&block)
        schema.graphql_schema_string
      end
    end
  end
end
