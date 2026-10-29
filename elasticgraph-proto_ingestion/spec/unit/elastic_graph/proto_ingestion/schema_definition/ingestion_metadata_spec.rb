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
      RSpec.describe Schema, "ingestion metadata" do
        it "generates complete field, scalar, enum, and abstract-type metadata" do
          config = ingestion_config do |s|
            s.scalar_type("Money") do |t|
              t.mapping type: "keyword"
              t.protobuf type: "string"
            end
            s.enum_type("Status") { |t| t.values "ACTIVE", "onHold" }
            s.object_type("Box") { |t| t.field "size", "Int", name_in_index: "private_size" }
            s.object_type("RoundSphere") { |t| t.field "radius", "Float" }
            s.union_type("Shape") { |t| t.subtypes "Box", "RoundSphere" }
            s.object_type "Product" do |t|
              t.field "id", "ID!"
              t.field "name", "String!", name_in_index: "private_name"
              t.field "price", "Money"
              t.field "released_dates", "[[Date!]!]!"
              t.field "status", "Status"
              t.field "shape", "Shape"
              t.index "products"
            end
          end

          expect(config.fetch("package_name")).to eq("elasticgraph")
          types = config.fetch("types_by_name")
          expect(types.keys).to contain_exactly("Box", "Date", "Float", "ID", "Int", "Money", "Product", "Shape", "RoundSphere", "Status", "String")
          expect(types.fetch("Product")).to eq("fields_by_name" => {
            "id" => {"type" => "ID!", "name_in_index" => "id"},
            "name" => {"type" => "String!", "name_in_index" => "private_name"},
            "price" => {"type" => "Money", "name_in_index" => "price"},
            "released_dates" => {"type" => "[[Date!]!]!", "name_in_index" => "released_dates"},
            "status" => {"type" => "Status", "name_in_index" => "status"},
            "shape" => {"type" => "Shape", "name_in_index" => "shape"}
          })
          expect(types.fetch("Box")).to eq("fields_by_name" => {"size" => {"type" => "Int", "name_in_index" => "private_size"}})
          expect(types.fetch("RoundSphere")).to eq("fields_by_name" => {"radius" => {"type" => "Float", "name_in_index" => "radius"}})
          expect(types.fetch("Shape")).to eq("subtypes_by_field_name" => {"box" => "Box", "round_sphere" => "RoundSphere"})
          expect(types.fetch("Status")).to eq(
            "enum_values_by_name" => {"STATUS_ACTIVE" => "ACTIVE", "STATUS_ON_HOLD" => "onHold"},
            "enum_zero_value" => "STATUS_UNSPECIFIED"
          )
          expect(types.fetch("Money")).to eq("scalar" => "Money")
          expect(types.fetch("String")).to eq("scalar" => "String")
        end

        it "records every built-in scalar, preserving its canonical name after a rename or wire-type override" do
          config = ingestion_config(type_name_overrides: {"JsonSafeLong" => "SafeLong"}) do |s|
            s.on_built_in_types { |type| type.protobuf type: "string" if type.name == "DateTime" }
            scalar_names = s.state.scalar_types_by_name.keys
            s.object_type "Event" do |t|
              scalar_names.each { |name| t.field name.downcase, name }
              t.index "events"
            end
          end

          types = config.fetch("types_by_name")
          expect(types.except("Event").transform_values { |type| type.fetch("scalar") }).to eq(
            "Boolean" => "Boolean", "Cursor" => "Cursor", "Date" => "Date", "DateTime" => "DateTime",
            "Float" => "Float", "ID" => "ID", "Int" => "Int", "LocalTime" => "LocalTime",
            "LongString" => "LongString", "SafeLong" => "JsonSafeLong", "String" => "String",
            "TimeZone" => "TimeZone", "Untyped" => "Untyped"
          )
          expect(types.fetch("Event").fetch("fields_by_name").fetch("safelong")).to eq("type" => "SafeLong", "name_in_index" => "safelong")
        end

        it "loads complete typed metadata after a YAML dump round trip" do
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
          expect(metadata.types_by_name.fetch("Status").enum_values_by_name).to eq("STATUS_ACTIVE" => "ACTIVE", "STATUS_ON_HOLD" => "onHold")
          expect(metadata.types_by_name.fetch("Status").enum_zero_value).to eq("STATUS_UNSPECIFIED")
          expect(RuntimeMetadata::Schema.from_hash(metadata.to_dumpable_hash)).to eq(metadata)
          expect(extension.load_extension.extension_class).to be(IndexerExtension)
        end

        it "restores defaults for unused metadata attributes" do
          expect(RuntimeMetadata::Schema.from_hash({"package_name" => "empty"}).types_by_name).to eq({})
          expect(RuntimeMetadata::Type.from_hash({})).to eq(RuntimeMetadata::Type.new)
        end

        def ingestion_config(**options, &block)
          dumped = define_proto_schema_results(**options, &block).runtime_metadata.to_dumpable_hash
          extension = dumped.fetch("indexer_extension_modules").last.fetch("extension_ref")
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
