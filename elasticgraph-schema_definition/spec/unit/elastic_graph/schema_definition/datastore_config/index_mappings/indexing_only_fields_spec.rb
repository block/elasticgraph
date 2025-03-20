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
    RSpec.describe "Datastore config index mappings -- indexing-only fields" do
      include_context "IndexMappingsSpecSupport"

      it "allows indexing-only fields to specify their customized mapping" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"

            t.field "date", "String", indexing_only: true do |f|
              f.mapping type: "date"
            end

            t.index "my_type"
          end
        end

        expect(mapping.dig("properties", "date")).to eq({"type" => "date"})
      end

      it "allows indexing-only fields to be objects with nested fields" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "NestedType" do |t|
            t.field "name", "String!"
          end

          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "nested", "NestedType!", indexing_only: true

            t.index "my_type"
          end
        end

        expect(mapping.dig("properties", "nested")).to eq({
          "properties" => {
            "name" => {"type" => "keyword"}
          }
        })
      end

      it "raises an error when same mapping field is defined twice with different mapping types" do
        expect {
          index_mapping_for "cards" do |s|
            s.object_type "Card" do |t|
              t.field "id", "ID!"
              t.index "cards"
              t.field "meta", "Int"

              t.field "meta", "String", indexing_only: true do |f|
                f.mapping type: "text"
              end
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Duplicate indexing field", "Card", "meta", "graphql_only: true")
      end
    end
  end
end
