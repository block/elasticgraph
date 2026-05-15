# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "object_type_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata for a namespace type" do
      include_context "object type metadata support"

      it "auto-wires the `:namespace_ref` resolver for a no-arg field on `Query` that returns a namespace type" do
        metadata = object_type_metadata_for "Query" do |s|
          s.namespace_type "OlapQuery"
          s.on_root_query_type do |t|
            t.field "olap", "OlapQuery!"
          end
        end

        expect(metadata.graphql_fields_by_name.fetch("olap").resolver).to eq(
          configured_graphql_resolver(:namespace_ref)
        )
      end

      it "auto-wires the `:namespace_ref` resolver for a no-arg field on a namespace type that returns another namespace type" do
        metadata = object_type_metadata_for "OlapQuery" do |s|
          s.namespace_type "OlapQuery" do |t|
            t.field "domain", "DomainQuery"
          end
          s.namespace_type "DomainQuery"
          s.on_root_query_type { |t| t.field "olap", "OlapQuery" }
        end

        expect(metadata.graphql_fields_by_name.fetch("domain").resolver).to eq(
          configured_graphql_resolver(:namespace_ref)
        )
      end

      it "auto-wires the `:namespace_ref` resolver for a no-arg field on a regular indexed type that returns a namespace type" do
        metadata = object_type_metadata_for "Widget" do |s|
          s.namespace_type "DomainQuery"
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "domain", "DomainQuery"
            t.index "widgets"
          end
          s.on_root_query_type { |t| t.field "domain", "DomainQuery" }
        end

        expect(metadata.graphql_fields_by_name.fetch("domain").resolver).to eq(
          configured_graphql_resolver(:namespace_ref)
        )
      end

      it "does not auto-wire a resolver on a field that returns a regular object type, even when its parent is a namespace type" do
        expect {
          object_type_metadata_for "OlapQuery" do |s|
            s.object_type "Plain" do |t|
              t.field "id", "ID"
            end
            s.namespace_type "OlapQuery" do |t|
              t.field "plain", "Plain"
            end
            s.on_root_query_type { |t| t.field "olap", "OlapQuery" }
          end
        }.to raise_error(Errors::SchemaError, a_string_including("`OlapQuery.plain` needs a resolver"))
      end

      it "does not override an explicit `resolver` on a field that returns a namespace type" do
        metadata = object_type_metadata_for "OlapQuery" do |s|
          s.namespace_type "OlapQuery" do |t|
            t.field "domain", "DomainQuery" do |f|
              f.resolve_with :get_record_field_value
            end
          end
          s.namespace_type "DomainQuery"
          s.on_root_query_type { |t| t.field "olap", "OlapQuery" }
        end

        expect(metadata.graphql_fields_by_name.fetch("domain").resolver).to eq(
          configured_graphql_resolver(:get_record_field_value)
        )
      end

      it "does not auto-wire a resolver on a field that takes arguments, even when it returns a namespace type" do
        expect {
          object_type_metadata_for "OlapQuery" do |s|
            s.namespace_type "OlapQuery" do |t|
              t.field "domain", "DomainQuery" do |f|
                f.argument "key", "String!"
              end
            end
            s.namespace_type "DomainQuery"
            s.on_root_query_type { |t| t.field "olap", "OlapQuery" }
          end
        }.to raise_error(Errors::SchemaError, a_string_including("`OlapQuery.domain` needs a resolver"))
      end

      it "respects an explicit `resolver` on a subfield of a namespace type (since the namespace type itself has no default resolver)" do
        metadata = object_type_metadata_for "OlapQuery" do |s|
          s.namespace_type "OlapQuery" do |t|
            t.field "name", "String" do |f|
              f.resolve_with :get_record_field_value
            end
          end
          s.on_root_query_type { |t| t.field "olap", "OlapQuery" }
        end

        expect(metadata.graphql_fields_by_name.fetch("name").resolver).to eq(
          configured_graphql_resolver(:get_record_field_value)
        )
      end
    end
  end
end
