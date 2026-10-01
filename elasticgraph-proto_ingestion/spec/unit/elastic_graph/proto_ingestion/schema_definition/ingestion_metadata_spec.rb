# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/scalar_coercion_adapters/valid_time_zones"
require "elastic_graph/proto_ingestion/schema_definition/api_extension"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # The indexer reads record structure from protobuf descriptors, so runtime metadata carries only
      # the ingestion facts those descriptors can't express.
      RSpec.describe Schema, "ingestion metadata" do
        it "registers the indexer extension with only the facts protobuf descriptors cannot express" do
          config = ingestion_config do |s|
            s.scalar_type("Money") do |t|
              t.mapping type: "keyword"
              t.protobuf type: "string"
            end
            s.enum_type("Color") { |t| t.values "RED", "BLUE" }
            s.enum_type("Status") { |t| t.values "ACTIVE", "onHold" }
            s.object_type("Box") { |t| t.field "size", "Int", name_in_index: "private_size" }
            s.object_type("Sphere") { |t| t.field "radius", "Float" }
            s.union_type("Shape") { |t| t.subtypes "Box", "Sphere" }
            s.object_type "Product" do |t|
              t.field "id", "ID!"
              t.field "name", "String!", name_in_index: "private_name"
              t.field "price", "Money"
              t.field "released", "Date"
              t.field "released_dates", "[[Date]]"
              t.field "views", "JsonSafeLong"
              t.field "large", "LongString"
              t.field "created_at", "DateTime"
              t.field "payload", "Untyped"
              t.field "color", "Color"
              t.field "status", "Status"
              t.field "shape", "Shape"
              t.index "products"
            end
          end

          expect(config).to eq(
            "package_name" => "elasticgraph",
            "fields" => {
              "Box" => {"size" => {"name_in_index" => "private_size"}},
              "Product" => {
                "name" => {"name_in_index" => "private_name"},
                "released" => {"type" => "Date"},
                "released_dates" => {"type" => "Date"},
                "views" => {"type" => "JsonSafeLong"},
                "payload" => {"type" => "Untyped"}
              }
            },
            "enum_values" => {"Status" => {"STATUS_ON_HOLD" => "onHold"}}
          )
        end

        it "names a scalar whose ingestion rules differ from its wire type's default scalar" do
          config = ingestion_config do |s|
            s.on_built_in_types { |type| type.protobuf type: "string" if type.name == "DateTime" }
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "at", "DateTime"
              t.field "time", "LocalTime"
              t.index "events"
            end
          end

          expect(config.fetch("fields")).to eq("Event" => {"at" => {"type" => "DateTime"}, "time" => {"type" => "LocalTime"}})
        end

        it "records the canonical scalar of a renamed built-in scalar" do
          config = ingestion_config(type_name_overrides: {"JsonSafeLong" => "SafeLong"}) do |s|
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "visits", "SafeLong"
              t.index "events"
            end
          end

          expect(config.fetch("fields")).to eq("Event" => {"visits" => {"type" => "SafeLong", "scalar" => "JsonSafeLong"}})
        end

        it "includes the valid time zones only when a field needs them" do
          with_zone = ingestion_config do |s|
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "zone", "TimeZone"
              t.index "events"
            end
          end

          expect(with_zone.fetch("fields")).to eq("Event" => {"zone" => {"type" => "TimeZone"}})
          expect(with_zone.fetch("time_zones")).to eq(GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.to_a)
          without_zone = ingestion_config do |s|
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.index "events"
            end
          end

          expect(without_zone).not_to include("time_zones")
        end

        it "can be loaded after dumping prunes empty override lists" do
          results = define_proto_schema_results do |s|
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.index "events"
            end
          end
          dumped = SchemaArtifacts::RuntimeMetadata::Schema.from_hash(results.runtime_metadata.to_dumpable_hash)
          extension = dumped.indexer_extension_modules.last.extension_ref

          expect(extension.fetch("config")).to eq("package_name" => "elasticgraph")
          expect(RuntimeSchema.new(instance_double(results.class, runtime_metadata: dumped)).package_name).to eq("elasticgraph")
        end

        def ingestion_config(**options, &block)
          extension = define_proto_schema_results(**options, &block).runtime_metadata.indexer_extension_modules.last.extension_ref
          expect(extension.except("config")).to eq(
            "name" => "ElasticGraph::ProtoIngestion::IndexerExtension",
            "require_path" => "elastic_graph/proto_ingestion/indexer_extension"
          )
          extension.fetch("config")
        end
      end
    end
  end
end
