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
            "types_by_name" => {
              "Box" => {"fields_by_name" => {"size" => {"name_in_index" => "private_size"}}},
              "Date" => {"scalar" => "Date"},
              "ID" => {"scalar" => "ID"},
              "JsonSafeLong" => {"scalar" => "JsonSafeLong"},
              "Money" => {"scalar" => "Money"},
              "Product" => {"fields_by_name" => {
                "id" => {"type" => "ID"},
                "price" => {"type" => "Money"},
                "name" => {"name_in_index" => "private_name"},
                "released" => {"type" => "Date"},
                "released_dates" => {"type" => "Date"},
                "views" => {"type" => "JsonSafeLong"},
                "payload" => {"type" => "Untyped"}
              }},
              "Status" => {"enum_values_by_name" => {"STATUS_ON_HOLD" => "onHold"}},
              "Untyped" => {"scalar" => "Untyped"}
            }
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

          expect(config.fetch("types_by_name")).to eq(
            "DateTime" => {"scalar" => "DateTime"},
            "Event" => {"fields_by_name" => {"id" => {"type" => "ID"}, "at" => {"type" => "DateTime"}, "time" => {"type" => "LocalTime"}}},
            "ID" => {"scalar" => "ID"},
            "LocalTime" => {"scalar" => "LocalTime"}
          )
        end

        it "records the canonical scalar of a renamed built-in scalar" do
          config = ingestion_config(type_name_overrides: {"JsonSafeLong" => "SafeLong"}) do |s|
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "visits", "SafeLong"
              t.index "events"
            end
          end

          expect(config.fetch("types_by_name")).to eq(
            "Event" => {"fields_by_name" => {"id" => {"type" => "ID"}, "visits" => {"type" => "SafeLong"}}},
            "ID" => {"scalar" => "ID"},
            "SafeLong" => {"scalar" => "JsonSafeLong"}
          )
        end

        it "names `TimeZone` fields so the indexer can validate them against `Support::VALID_TIME_ZONES`" do
          config = ingestion_config do |s|
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "zone", "TimeZone"
              t.index "events"
            end
          end

          expect(config).to eq(
            "package_name" => "elasticgraph",
            "types_by_name" => {
              "Event" => {"fields_by_name" => {"id" => {"type" => "ID"}, "zone" => {"type" => "TimeZone"}}},
              "ID" => {"scalar" => "ID"},
              "TimeZone" => {"scalar" => "TimeZone"}
            }
          )
        end

        it "covers every built-in scalar, including those with no metadata beyond their wire type" do
          config = ingestion_config do |s|
            scalar_names = s.state.scalar_types_by_name.keys
            s.object_type "Event" do |t|
              scalar_names.each { |name| t.field name.downcase, name }
              t.index "events"
            end
          end

          expect(config.fetch("types_by_name")).to eq(
            "Cursor" => {"scalar" => "Cursor"},
            "Date" => {"scalar" => "Date"},
            "Event" => {"fields_by_name" => {
              "cursor" => {"type" => "Cursor"},
              "date" => {"type" => "Date"},
              "id" => {"type" => "ID"},
              "jsonsafelong" => {"type" => "JsonSafeLong"},
              "localtime" => {"type" => "LocalTime"},
              "timezone" => {"type" => "TimeZone"},
              "untyped" => {"type" => "Untyped"}
            }},
            "ID" => {"scalar" => "ID"},
            "JsonSafeLong" => {"scalar" => "JsonSafeLong"},
            "LocalTime" => {"scalar" => "LocalTime"},
            "TimeZone" => {"scalar" => "TimeZone"},
            "Untyped" => {"scalar" => "Untyped"}
          )
        end

        it "loads typed metadata and the registered indexer extension after a YAML dump round trip" do
          results = define_proto_schema_results do |s|
            s.proto_schema_artifacts package_name: "custom.package"
            s.enum_type("Status") { |t| t.values "ACTIVE", "onHold" }
            s.object_type "Event" do |t|
              t.field "id", "ID"
              t.field "date", "Date", name_in_index: "private_date"
              t.field "status", "Status"
              t.index "events"
            end
          end
          dumped = SchemaArtifacts::RuntimeMetadata::Schema.from_hash(YAML.safe_load(YAML.dump(results.runtime_metadata.to_dumpable_hash)))
          extension = dumped.indexer_extension_modules.last
          metadata = RuntimeMetadata::Schema.from_hash(extension.extension_ref.fetch("config"))

          expect(metadata.package_name).to eq("custom.package")
          expect(metadata.types_by_name.fetch("Event").fields_by_name.fetch("date")).to eq(
            RuntimeMetadata::Field.new(name_in_index: "private_date", type: "Date")
          )
          expect(metadata.types_by_name.fetch("Date").scalar).to eq("Date")
          expect(metadata.types_by_name.fetch("Status").enum_values_by_name).to eq("STATUS_ON_HOLD" => "onHold")
          expect(metadata.to_dumpable_hash).to eq(extension.extension_ref.fetch("config"))
          expect(extension.load_extension.extension_class).to be(IndexerExtension)
        end

        it "omits empty metadata and restores defaults when loading it" do
          config = ingestion_config do |s|
            s.object_type "Event" do |t|
              t.field "id", "String"
              t.index "events"
            end
          end

          expect(config).to eq("package_name" => "elasticgraph")
          expect(RuntimeMetadata::Schema.from_hash(config).types_by_name).to eq({})
          expect(RuntimeMetadata::Type.from_hash({})).to eq(RuntimeMetadata::Type.new)
          expect(RuntimeMetadata::Field.from_hash({})).to eq(RuntimeMetadata::Field.new)
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
