# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #index_definitions_by_name" do
      include_context "RuntimeMetadata support"

      let(:type_definition_orders) do
        types = ["NestedFields", "MyType"]
        [types, types.reverse]
      end

      it "dumps the `route_with` value" do
        widgets = index_definition_metadata_for("widgets") do |i|
          i.route_with "group_id"
        end
        expect(widgets.route_with).to eq "group_id"
      end

      it "dumps the `route_with` field's `name_in_index`" do
        widgets = index_definition_metadata_for("widgets") do |i|
          i.route_with "group_id_gql"
        end
        expect(widgets.route_with).to eq "group_id_index"
      end

      it "supports nested `route_with` fields regardless of definition order, using the `name_in_index` at each layer" do
        type_definition_orders.each do |type_definition_order|
          widgets = index_definition_metadata_for("widgets", type_definition_order: type_definition_order) do |i|
            i.route_with "nested_fields_gql.some_id_gql"
          end
          expect(widgets.route_with).to eq "nested_fields_index.some_id_index"
        end
      end

      it "defaults `route_with` to `id` because that's the default routing the datastore uses" do
        components = index_definition_metadata_for("components")
        expect(components.route_with).to eq "id"
      end

      it "dumps the `rollover` options, if set" do
        widgets = index_definition_metadata_for("widgets") do |i|
          i.rollover :monthly, "created_at"
        end
        expect(widgets.rollover).to eq SchemaArtifacts::RuntimeMetadata::IndexDefinition::Rollover.new(
          frequency: :monthly,
          timestamp_field_path: "created_at"
        )

        components = index_definition_metadata_for("components")
        expect(components.rollover).to eq nil
      end

      it "dumps the `rollover` timestamp field's `name_in_index`" do
        widgets = index_definition_metadata_for("widgets") do |i|
          i.rollover :monthly, "created_at_gql"
        end
        expect(widgets.rollover).to eq SchemaArtifacts::RuntimeMetadata::IndexDefinition::Rollover.new(
          frequency: :monthly,
          timestamp_field_path: "created_at_index"
        )
      end

      it "supports nested `rollover` timestamp fields regardless of definition order, using the `name_in_index` at each layer" do
        type_definition_orders.each do |type_definition_order|
          widgets = index_definition_metadata_for("widgets", type_definition_order: type_definition_order) do |i|
            i.rollover :monthly, "nested_fields_gql.some_timestamp_gql"
          end
          expect(widgets.rollover).to eq SchemaArtifacts::RuntimeMetadata::IndexDefinition::Rollover.new(
            frequency: :monthly,
            timestamp_field_path: "nested_fields_index.some_timestamp_index"
          )
        end
      end

      it "dumps the `default_sort_fields`" do
        widgets = index_definition_metadata_for("widgets") do |i|
          i.default_sort "created_at", :asc, "group_id", :desc
        end

        expect(widgets.default_sort_fields).to eq [
          sort_field_with(field_path: "created_at", direction: :asc),
          sort_field_with(field_path: "group_id", direction: :desc)
        ]
      end

      it "defaults `default_sort_fields` to `[]`" do
        widgets = index_definition_metadata_for("widgets")

        expect(widgets.default_sort_fields).to eq []
      end

      it "dumps the `default_sort_fields` `name_in_index`" do
        widgets = index_definition_metadata_for("widgets") do |i|
          i.default_sort "created_at_gql", :asc, "group_id_gql", :desc
        end

        expect(widgets.default_sort_fields).to eq [
          sort_field_with(field_path: "created_at_index", direction: :asc),
          sort_field_with(field_path: "group_id_index", direction: :desc)
        ]
      end

      it "supports nested `default_sort_fields`, correctly using `name_in_index` at each layer" do
        widgets = index_definition_metadata_for("widgets") do |i|
          i.default_sort "nested_fields_gql.some_timestamp_gql", :asc, "nested_fields_gql.some_id_gql", :desc
        end
        expect(widgets.default_sort_fields).to eq [
          sort_field_with(field_path: "nested_fields_index.some_timestamp_index", direction: :asc),
          sort_field_with(field_path: "nested_fields_index.some_id_index", direction: :desc)
        ]
      end

      it "raises a clear error when a sort field has not been defined" do
        expect {
          index_definition_metadata_for("widgets") do |i|
            i.default_sort "unknown_field", :asc
          end
        }.to raise_error(Errors::SchemaError, a_string_including("Field `MyType.unknown_field` cannot be resolved, but it is referenced as an index `default_sort` field"))
      end

      it "allows a referenced sort field to be indexing-only since it need not be exposed to GraphQL clients" do
        expect {
          index_definition_metadata_for("widgets", on_my_type: ->(t) { t.field "index_value", "String", indexing_only: true }) do |i|
            i.default_sort "index_value", :asc
          end
        }.not_to raise_error
      end

      it "raises a clear error when a nested sort field references a type that does not exist", :dont_validate_graphql_schema do
        expect {
          index_definition_metadata_for("widgets", on_my_type: ->(t) { t.field "options", "Opts" }) do |i|
            i.default_sort "options.unknown_field", :asc
          end
        }.to raise_error(Errors::SchemaError, a_string_including("Type `Opts` cannot be resolved"))
      end

      describe "#current_sources" do
        it "only contains `#{SELF_RELATIONSHIP_NAME}` on a index that has no `sourced_from` fields (but has fields)" do
          current_sources = current_sources_for "widgets" do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end

          expect(current_sources).to contain_exactly SELF_RELATIONSHIP_NAME
        end

        it "includes the sources of all `sourced_from` fields defined on the index" do
          current_sources = current_sources_for "components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "widget_type", "String" do |f|
                f.sourced_from "widget", "type"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(current_sources).to contain_exactly SELF_RELATIONSHIP_NAME, "widget"
        end

        it "considers `indexing_only` fields" do
          current_sources = current_sources_for "components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String", indexing_only: true do |f|
                f.sourced_from "widget", "name"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(current_sources).to contain_exactly SELF_RELATIONSHIP_NAME, "widget"
        end

        it "omits `#{SELF_RELATIONSHIP_NAME}` when _every_ field is a `sourced_from` field" do
          current_sources = current_sources_for "components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID" do |f|
                f.sourced_from "widget", "component_id"
              end

              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "widget_type", "String" do |f|
                f.sourced_from "widget", "type"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_id", "ID"
              t.index "widgets"
            end
          end

          expect(current_sources).to contain_exactly "widget"
        end

        it "considers `sourced_from` fields on embedded types" do
          current_sources = current_sources_for "components" do |s|
            s.object_type "ComponentWidgetFields" do |t|
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "widget_type", "String" do |f|
                f.sourced_from "widget", "type"
              end
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "widget_fields", "ComponentWidgetFields"
              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(current_sources).to contain_exactly SELF_RELATIONSHIP_NAME, "widget"
        end

        it "considers the sources of all subtypes of a type union" do
          current_sources = current_sources_for "widgets_or_components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String", indexing_only: true do |f|
                f.sourced_from "widget", "name"
              end
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end

            s.union_type "WidgetOrComponent" do |t|
              t.subtypes "Widget", "Component"
              t.index "widgets_or_components"
            end
          end

          expect(current_sources).to contain_exactly SELF_RELATIONSHIP_NAME, "widget"
        end

        it "considers the sources of all subtypes of an interface" do
          current_sources = current_sources_for "types_with_ids" do |s|
            s.object_type "Component" do |t|
              t.implements "TypeWithID"
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String", indexing_only: true do |f|
                f.sourced_from "widget", "name"
              end
            end

            s.object_type "Widget" do |t|
              t.implements "TypeWithID"
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end

            s.interface_type "TypeWithID" do |t|
              t.field "id", "ID!"
              t.index "types_with_ids"
            end
          end

          expect(current_sources).to contain_exactly SELF_RELATIONSHIP_NAME, "widget"
        end

        def current_sources_for(index_name, &block)
          define_schema(&block)
            .runtime_metadata
            .index_definitions_by_name
            .fetch(index_name)
            .current_sources
        end
      end

      describe "#fields_by_path" do
        it "records the source of each field, defaulting to `#{SELF_RELATIONSHIP_NAME}` for fields that do not use `sourced_from`" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "widget_type", "String" do |f|
                f.sourced_from "widget", "type"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "widget_name" => index_field_with(source: "widget"),
            "widget_type" => index_field_with(source: "widget")
          })
        end

        it "uses dot-separated paths for keys" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "ComponentWidgetFields" do |t|
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in
              t.field "id", "ID"

              t.field "name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "type", "String" do |f|
                f.sourced_from "widget", "type"
              end
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "widget_fields", "ComponentWidgetFields"
              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "widget_fields.id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "widget_fields.name" => index_field_with(source: "widget"),
            "widget_fields.type" => index_field_with(source: "widget")
          })
        end

        it "includes `indexing_only` fields and excludes `graphql_only` fields" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "name", "String", graphql_only: true
              t.field "type", "String", indexing_only: true
              t.index "components"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "type" => index_field_with(source: SELF_RELATIONSHIP_NAME)
          })
        end

        it "uses the `name_in_index` instead of the GraphQL name of a field" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "ComponentWidgetFields" do |t|
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in
              t.field "id", "ID"

              t.field "name", "String", name_in_index: "name2" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "type", "String" do |f|
                f.sourced_from "widget", "type"
              end
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "widget_fields", "ComponentWidgetFields", name_in_index: "nested"
              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "nested.id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "nested.name2" => index_field_with(source: "widget"),
            "nested.type" => index_field_with(source: "widget")
          })
        end

        it "includes fields from all subtypes of a type union" do
          fields_by_path = fields_by_path_for "widgets_or_components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_name", "String", indexing_only: true do |f|
                f.sourced_from "widget", "name"
              end
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_id", "ID"
              t.index "widgets"
            end

            s.union_type "WidgetOrComponent" do |t|
              t.subtypes "Widget", "Component"
              t.index "widgets_or_components"
            end
          end

          expect(fields_by_path).to eq({
            "component_id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "name" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "type" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "widget_name" => index_field_with(source: "widget")
          })
        end

        it "considers the sources of all subtypes of an interface" do
          fields_by_path = fields_by_path_for "types_with_ids" do |s|
            s.object_type "Component" do |t|
              t.implements "TypeWithID"
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_name", "String", indexing_only: true do |f|
                f.sourced_from "widget", "name"
              end
            end

            s.object_type "Widget" do |t|
              t.implements "TypeWithID"
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "type", "String"
              t.field "component_id", "ID"
              t.index "widgets"
            end

            s.interface_type "TypeWithID" do |t|
              t.field "id", "ID!"
              t.index "types_with_ids"
            end
          end

          expect(fields_by_path).to eq({
            "component_id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "name" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "type" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "widget_name" => index_field_with(source: "widget")
          })
        end

        it "propagates an alternative source from a parent field to a child field" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "NameAndType" do |t|
              t.field "name", "String"
              t.field "type", "String"
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_name_and_type", "NameAndType" do |f|
                f.sourced_from "widget", "name_and_type"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name_and_type", "NameAndType"
              t.field "component_id", "ID"
              t.index "widgets"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "widget_name_and_type.name" => index_field_with(source: "widget"),
            "widget_name_and_type.type" => index_field_with(source: "widget")
          })
        end

        it "indicates where the subfields of `#{LIST_COUNTS_FIELD}` are sourced from" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "tags", "[String!]!"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "widget_tags", "[String!]" do |f|
                f.sourced_from "widget", "tags"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "tags", "[String!]!"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(fields_by_path.select { |k, v| k.start_with?(LIST_COUNTS_FIELD) }).to eq({
            "#{LIST_COUNTS_FIELD}.tags" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "#{LIST_COUNTS_FIELD}.widget_tags" => index_field_with(source: "widget")
          })
        end

        it "correctly uses `#{LIST_COUNTS_FIELD_PATH_KEY_SEPARATOR}` to separate path parts under `__counts`" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "Tags" do |t|
              t.field "tags", "[String!]!"
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "subfield", "Tags"
              t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

              t.field "widget_name", "String" do |f|
                f.sourced_from "widget", "name"
              end

              t.field "widget_subfield", "Tags" do |f|
                f.sourced_from "widget", "subfield"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.field "subfield", "Tags"
              t.field "component_ids", "[ID!]!"
              t.index "widgets"
            end
          end

          expect(fields_by_path.select { |k, v| k.start_with?(LIST_COUNTS_FIELD) }).to eq({
            "#{LIST_COUNTS_FIELD}.subfield|tags" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "#{LIST_COUNTS_FIELD}.widget_subfield|tags" => index_field_with(source: "widget")
          })
        end

        it "deals with `nested` list fields which have no `object` list fields correctly" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "NameAndType" do |t|
              t.field "name", "String"
              t.field "types", "[String]"
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_name_and_type", "[NameAndType!]" do |f|
                f.mapping type: "nested"
                f.sourced_from "widget", "name_and_type"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name_and_type", "[NameAndType!]!" do |f|
                f.mapping type: "nested"
              end
              t.field "component_id", "ID"
              t.index "widgets"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "widget_name_and_type.name" => index_field_with(source: "widget"),
            "widget_name_and_type.types" => index_field_with(source: "widget"),
            "#{LIST_COUNTS_FIELD}.widget_name_and_type" => index_field_with(source: "widget"),
            "widget_name_and_type.#{LIST_COUNTS_FIELD}.types" => index_field_with(source: "widget")
          })
        end

        it "deals with `nested` list fields which have `object` list fields correctly" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "NameAndType" do |t|
              t.field "name", "String"
              t.field "types", "[String]"
            end

            s.object_type "Details" do |t|
              t.field "size", "Int"
              t.field "name_and_type", "[NameAndType!]!" do |f|
                f.mapping type: "object"
              end
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_details", "[Details!]" do |f|
                f.mapping type: "nested"
                f.sourced_from "widget", "details"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "details", "[Details!]!" do |f|
                f.mapping type: "nested"
              end
              t.field "component_id", "ID"
              t.index "widgets"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "#{LIST_COUNTS_FIELD}.widget_details" => index_field_with(source: "widget"),
            "widget_details.#{LIST_COUNTS_FIELD}.name_and_type" => index_field_with(source: "widget"),
            "widget_details.#{LIST_COUNTS_FIELD}.name_and_type|name" => index_field_with(source: "widget"),
            "widget_details.#{LIST_COUNTS_FIELD}.name_and_type|types" => index_field_with(source: "widget"),
            "widget_details.name_and_type.name" => index_field_with(source: "widget"),
            "widget_details.name_and_type.types" => index_field_with(source: "widget"),
            "widget_details.size" => index_field_with(source: "widget")
          })
        end

        it "deals with `object` list fields which have `nested` list fields correctly" do
          fields_by_path = fields_by_path_for "components" do |s|
            s.object_type "NameAndType" do |t|
              t.field "name", "String"
              t.field "types", "[String]"
            end

            s.object_type "Details" do |t|
              t.field "size", "Int"
              t.field "name_and_type", "[NameAndType!]!" do |f|
                f.mapping type: "nested"
              end
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.relates_to_one "widget", "Widget", via: "component_id", dir: :in

              t.field "widget_details", "[Details!]" do |f|
                f.mapping type: "object"
                f.sourced_from "widget", "details"
              end

              t.index "components"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "details", "[Details!]!" do |f|
                f.mapping type: "object"
              end
              t.field "component_id", "ID"
              t.index "widgets"
            end
          end

          expect(fields_by_path).to eq({
            "id" => index_field_with(source: SELF_RELATIONSHIP_NAME),
            "#{LIST_COUNTS_FIELD}.widget_details" => index_field_with(source: "widget"),
            "#{LIST_COUNTS_FIELD}.widget_details|name_and_type" => index_field_with(source: "widget"),
            "#{LIST_COUNTS_FIELD}.widget_details|size" => index_field_with(source: "widget"),
            "widget_details.name_and_type.name" => index_field_with(source: "widget"),
            "widget_details.name_and_type.types" => index_field_with(source: "widget"),
            "widget_details.name_and_type.#{LIST_COUNTS_FIELD}.types" => index_field_with(source: "widget"),
            "widget_details.size" => index_field_with(source: "widget")
          })
        end

        it "aligns the `#{LIST_COUNTS_FIELD}` subfields with mapping generated for `#{LIST_COUNTS_FIELD}`" do
          results = define_schema do |schema|
            schema.object_type "TeamDetails" do |t|
              t.field "uniform_colors", "[String!]!"

              # `details.count` isn't really meaningful on our team model here, but we need this field
              # to test that ElasticGraph handles a domain field named `count` even while it offers a
              # `count` operator on list fields.
              t.field schema.state.schema_elements.count, "Int"
            end

            schema.object_type "Team" do |t|
              t.field "id", "ID!"
              t.field "current_name", "String"
              t.field "past_names", "[String!]!"
              t.field "won_championships_at", "[DateTime!]!"
              t.field "details", "TeamDetails"
              t.field "stadium_location", "GeoLocation"
              t.field "forbes_valuations", "[JsonSafeLong!]!"

              t.field "current_players_nested", "[Player!]!" do |f|
                f.mapping type: "nested"
              end

              t.field "current_players_object", "[Player!]!" do |f|
                f.mapping type: "object"
              end

              t.field "seasons_nested", "[TeamSeason!]!" do |f|
                f.mapping type: "nested"
              end

              t.field "seasons_object", "[TeamSeason!]!" do |f|
                f.mapping type: "object"
              end

              t.index "teams"
            end

            schema.object_type "Player" do |t|
              t.field "name", "String"
              t.field "nicknames", "[String!]!"

              t.field "seasons_nested", "[PlayerSeason!]!" do |f|
                f.mapping type: "nested"
              end

              t.field "seasons_object", "[PlayerSeason!]!" do |f|
                f.mapping type: "object"
              end
            end

            schema.object_type "TeamSeason" do |t|
              t.field "year", "Int"
              t.field "notes", "[String!]!"
              t.field "started_at", "DateTime"
              t.field "won_games_at", "[DateTime!]!"

              t.field "players_nested", "[Player!]!" do |f|
                f.mapping type: "nested"
              end

              t.field "players_object", "[Player!]!" do |f|
                f.mapping type: "object"
              end
            end

            schema.object_type "PlayerSeason" do |t|
              t.field "year", "Int"
              t.field "games_played", "Int"
              t.paginated_collection_field "awards", "String"
            end
          end

          from_runtime_metadata = results
            .runtime_metadata
            .index_definitions_by_name.fetch("teams")
            .fields_by_path.keys
            .select { |path| path.include?(LIST_COUNTS_FIELD) }

          from_mapping = build_count_paths_from_mapping(
            results.index_mappings_by_index_def_name.fetch("teams")
          )

          expect(from_runtime_metadata.sort.join("\n")).to eq from_mapping.sort.join("\n")
          expect(logged_output).to include "a `TeamDetails.count` field exists"
        end

        def fields_by_path_for(index_name, &block)
          define_schema(&block)
            .runtime_metadata
            .index_definitions_by_name
            .fetch(index_name)
            .fields_by_path
        end

        def build_count_paths_from_mapping(mapping)
          mapping.fetch("properties").flat_map do |field_name, value|
            if field_name == LIST_COUNTS_FIELD
              value.fetch("properties").keys.map { |subfield| "#{LIST_COUNTS_FIELD}.#{subfield}" }
            elsif value.key?("properties")
              build_count_paths_from_mapping(value).map do |subfield|
                "#{field_name}.#{subfield}"
              end
            else
              []
            end
          end
        end
      end

      def index_definition_metadata_for(name, type_definition_order: ["NestedFields", "MyType"], on_my_type: nil, **options, &block)
        type_defs = {
          "NestedFields" => ->(t) do
            t.field "some_id_gql", "ID", name_in_index: "some_id_index"
            t.field "some_timestamp_gql", "DateTime", name_in_index: "some_timestamp_index"
          end,

          "MyType" => ->(t) do
            t.field "id", "ID!"
            t.field "group_id", "ID!"
            t.field "group_id_gql", "ID", name_in_index: "group_id_index"
            t.field "created_at", "DateTime!"
            t.field "created_at_gql", "DateTime!", name_in_index: "created_at_index"
            t.field "nested_fields_gql", "NestedFields", name_in_index: "nested_fields_index"
            on_my_type&.call(t)
            t.index(name, **options, &block)
          end
        }

        runtime_metadata = define_schema do |s|
          type_definition_order.each do |type_name|
            s.object_type(type_name, &type_defs.fetch(type_name))
          end
        end.runtime_metadata

        runtime_metadata
          .index_definitions_by_name
          .fetch(name)
      end
    end
  end
end
