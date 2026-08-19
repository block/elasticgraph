# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Covers which types get a message: the types a publisher can send events for, and every type
      # they reference.
      RSpec.describe Schema, "ingestible types" do
        it "generates a message for a `sourced_from` source type that has no index of its own" do
          proto = define_proto_schema do |s|
            define_component_type(s)

            s.object_type "ComponentDesign" do |t|
              t.field "id", "ID!"
              t.field "component_id", "ID"
              t.field "designer_name", "String"
            end
          end

          expect(proto_type_def_from(proto, "ComponentDesign")).to eq(<<~PROTO.strip)
            message ComponentDesign {
              string id = 1;
              string component_id = 2;
              string designer_name = 3;
              // Next field number: 4
            }
          PROTO
        end

        it "generates a message for a type referenced by a non-indexed source type" do
          proto = define_proto_schema do |s|
            define_component_type(s)

            s.object_type "ComponentDesign" do |t|
              t.field "id", "ID!"
              t.field "component_id", "ID"
              t.field "designer_name", "String"
              t.field "studio", "DesignStudio"
            end

            s.object_type "DesignStudio" do |t|
              t.field "name", "String"
            end
          end

          expect(proto_type_def_from(proto, "DesignStudio")).to eq(<<~PROTO.strip)
            message DesignStudio {
              string name = 1;
              // Next field number: 2
            }
          PROTO
        end

        it "generates a oneof wrapper and subtype messages for an abstract source type" do
          proto = define_proto_schema do |s|
            define_component_type(s)

            s.interface_type "ComponentDesign" do |t|
              t.field "id", "ID!"
              t.field "component_id", "ID"
              t.field "designer_name", "String"
            end

            s.object_type "InternalComponentDesign" do |t|
              t.implements "ComponentDesign"
              t.field "id", "ID!"
              t.field "component_id", "ID"
              t.field "designer_name", "String"
            end
          end

          expect(proto_type_def_from(proto, "ComponentDesign")).to eq(<<~PROTO.strip)
            message ComponentDesign {
              oneof value {
                .elasticgraph.InternalComponentDesign internal_component_design = 1;
              }
              // Next field number: 2
            }
          PROTO

          expect(proto_type_def_from(proto, "InternalComponentDesign")).to eq(<<~PROTO.strip)
            message InternalComponentDesign {
              string id = 1;
              string component_id = 2;
              string designer_name = 3;
              // Next field number: 4
            }
          PROTO
        end

        it "generates no message for a derived indexing type, since no publisher sends its events" do
          proto = define_proto_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "workspace_id", "ID"
              t.field "name", "String"
              t.index "widgets"

              t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
                derive.immutable_value "name", from: "name"
              end
            end

            s.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "widget_workspaces"
            end
          end

          expect(proto_type_def_from(proto, "Widget")).not_to be nil
          expect(proto_type_def_from(proto, "WidgetWorkspace")).to be nil
        end

        it "generates no message for a type that no ingestible type references" do
          proto = define_proto_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String"
              t.index "widgets"
            end

            s.object_type "Unreferenced" do |t|
              t.field "id", "ID!"
            end
          end

          expect(proto_type_def_from(proto, "Unreferenced")).to be nil
        end

        # Defines an indexed type with a top-level `sourced_from` field fed by `ComponentDesign`.
        def define_component_type(schema)
          schema.object_type "Component" do |t|
            t.field "id", "ID!"
            t.field "name", "String"

            t.field "designer_name", "String" do |f|
              f.sourced_from "design", "designer_name"
            end

            t.relates_to_one "design", "ComponentDesign", via: "component_id", dir: :in, indexing_only: true

            t.index "components" do |i|
              i.has_had_multiple_sources!
            end
          end
        end
      end
    end
  end
end
