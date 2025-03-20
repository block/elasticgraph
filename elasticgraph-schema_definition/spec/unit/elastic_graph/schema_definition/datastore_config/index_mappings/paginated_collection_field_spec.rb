# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "index_mappings_spec_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Datastore config index mappings -- `paginated_collection_field`" do
      include_context "IndexMappingsSpecSupport"

      it "generates the mapping for a `paginated_collection_field`" do
        mapping = index_mapping_for "widgets" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.paginated_collection_field "names", "String"
            t.index "widgets"
          end
        end

        expect(mapping.dig("properties", "names")).to eq({"type" => "keyword"})
      end

      it "honors the `name_in_index` passed to `paginated_collection_field`" do
        mapping = index_mapping_for "widgets" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.paginated_collection_field "names", "String", name_in_index: "names2"
            t.index "widgets"
          end
        end

        expect(mapping.dig("properties")).not_to include("names")
        expect(mapping.dig("properties", "names2")).to eq({"type" => "keyword"})
      end

      it "honors the configured mapping type for a `paginated_collection_field`" do
        mapping = index_mapping_for "widgets" do |s|
          s.object_type "Color" do |t|
            t.field "red", "Int"
            t.field "green", "Int"
            t.field "blue", "Int"
          end

          s.object_type "Widget" do |t|
            t.field "id", "ID!"

            t.paginated_collection_field "colors_nested", "Color" do |f|
              f.mapping type: "nested"
            end

            t.paginated_collection_field "colors_object", "Color" do |f|
              f.mapping type: "object"
            end

            t.index "widgets"
          end
        end

        color_mapping = {"properties" => {"blue" => {"type" => "integer"}, "green" => {"type" => "integer"}, "red" => {"type" => "integer"}}}
        expect(mapping.dig("properties").select { |k| k =~ /color/ }).to eq({
          "colors_nested" => color_mapping.merge("type" => "nested"),
          "colors_object" => color_mapping.merge("type" => "object")
        })
      end
    end
  end
end
