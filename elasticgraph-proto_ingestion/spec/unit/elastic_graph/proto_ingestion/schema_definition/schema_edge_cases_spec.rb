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
      RSpec.describe Schema do
        it "returns an empty string when no indexed types are present" do
          proto = define_proto_schema do |s|
            s.object_type "Point" do |t|
              t.field "x", "Float"
              t.field "y", "Float"
            end
          end

          expect(proto).to eq("")
        end

        it "raises when enum values map to duplicate proto value names" do
          expect {
            define_proto_schema do |s|
              s.enum_type "Status" do |t|
                t.values "option", "OPTION"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Enum `Status` values `option` and `OPTION`",
            "duplicate proto enum value name `STATUS_OPTION`"
          ))
        end

        it "raises when an enum value conflicts with the generated zero value" do
          expect {
            define_proto_schema do |s|
              s.enum_type "Status" do |t|
                t.values "ACTIVE", "UNSPECIFIED"
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Enum `Status` value `UNSPECIFIED`",
            "conflicts with the generated zero value `STATUS_UNSPECIFIED`"
          ))
        end

        it "fully qualifies local type references so they do not conflict with contextual protobuf keywords" do
          proto = define_proto_schema do |s|
            s.enum_type "option" do |t|
              t.value "ACTIVE"
            end

            s.object_type "string" do |t|
              t.field "id", "ID"
            end

            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "option", "option"
              t.field "message", "string"
              t.index "events"
            end
          end

          expect(proto_type_def_from(proto, "option")).to start_with("enum option {")
          expect(proto_type_def_from(proto, "string")).to start_with("message string {")
          expect(proto_type_def_from(proto, "Event")).to include(
            ".elasticgraph.option option = 2;",
            ".elasticgraph.string message = 3;"
          )
        end

        it "raises when proto fields are accessed before the schema definition is complete" do
          expect {
            define_proto_schema do |s|
              s.object_type "Account" do |t|
                t.field "id", "ID"
                t.send(:proto_fields)
              end
            end
          }.to raise_error(Errors::SchemaError, "Cannot access `proto_fields` until the schema definition is complete.")
        end

        it "renders a shared enum only once when multiple indexed types reference it" do
          proto = define_proto_schema do |s|
            s.enum_type "Status" do |t|
              t.value "ACTIVE"
            end

            s.object_type "Account" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "accounts"
            end

            s.object_type "User" do |t|
              t.field "id", "ID"
              t.field "status", "Status"
              t.index "users"
            end
          end

          expect(proto.scan(/^enum Status \{/).size).to eq(1)
          expect(proto_type_def_from(proto, "Account")).to include(".elasticgraph.Status status = 2;")
          expect(proto_type_def_from(proto, "User")).to include(".elasticgraph.Status status = 2;")
        end
      end
    end
  end
end
