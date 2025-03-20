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
    RSpec.describe "Datastore config index mappings -- mapping customizations" do
      include_context "IndexMappingsSpecSupport"

      it "respects `mapping` customizations set on a field definition, allowing them to augment or replace the mapping of the base type" do
        mapping = index_mapping_for "my_type" do |s|
          s.scalar_type "MyText" do |t|
            t.json_schema type: "string"
            t.mapping type: "text"
          end

          s.object_type "MyType" do |t|
            t.field "id", "ID!"

            t.field "built_in_scalar_augmented", "String!" do |f|
              f.mapping enabled: true
            end

            t.field "built_in_scalar_replaced", "String!" do |f|
              f.mapping type: "text"
            end

            t.field "built_in_scalar_augmented_and_replaced", "String!" do |f|
              f.mapping type: "text", enabled: true
            end

            t.field "custom_scalar", "MyText!"

            t.field "custom_scalar_augmented", "MyText!" do |f|
              f.mapping analyzer: "hyper_text_analyzer"
            end

            t.field "custom_scalar_replaced", "MyText!" do |f|
              f.mapping type: "keyword"
            end

            t.field "custom_scalar_augmented_and_replaced", "MyText!" do |f|
              f.mapping type: "keyword", enabled: true
            end

            t.index "my_type"
          end
        end

        expect(mapping.fetch("properties")).to include(
          "id" => {"type" => "keyword"},
          "built_in_scalar_augmented" => {"type" => "keyword", "enabled" => true},
          "built_in_scalar_replaced" => {"type" => "text"},
          "built_in_scalar_augmented_and_replaced" => {"type" => "text", "enabled" => true},
          "custom_scalar" => {"type" => "text"},
          "custom_scalar_augmented" => {"type" => "text", "analyzer" => "hyper_text_analyzer"},
          "custom_scalar_replaced" => {"type" => "keyword"},
          "custom_scalar_augmented_and_replaced" => {"type" => "keyword", "enabled" => true}
        )
      end

      it "allows custom mapping options to be built up over multiple `mapping` calls" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"

            t.field "name", "String!" do |f|
              f.mapping type: "keyword"
              f.mapping enabled: true
              f.mapping type: "text" # demonstrate that the last value for an option wins
            end

            t.index "my_type"
          end
        end

        expect(mapping.dig("properties", "name")).to eq({"type" => "text", "enabled" => true})
      end

      it "prevents `mapping` on a field definition from overriding the mapping params in an unsupported way" do
        index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.index "my_type"

            t.field "description", "String!" do |f|
              expect {
                f.mapping unsupported_customizable: "abc123"
              }.to raise_error Errors::SchemaError, a_string_including("unsupported_customizable")

              expect(f.mapping_options).to be_empty
            end
          end
        end
      end

      it "allows the mapping type to be customized from a defined object type, omitting `properties` in that case" do
        define_point = lambda do |s|
          s.object_type "Point" do |t|
            t.field "x", "Float"
            t.field "y", "Float"
            t.mapping type: "point"
          end
        end

        define_my_type = lambda do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "location", "Point"
            t.index "my_type"
          end
        end

        # We should get the same mapping regardless of which type is defined first.
        type_before_reference_mapping = index_mapping_for "my_type" do |s|
          define_point.call(s)
          define_my_type.call(s)
        end

        type_after_reference_mapping = index_mapping_for "my_type" do |s|
          define_my_type.call(s)
          define_point.call(s)
        end

        expect(type_before_reference_mapping).to eq(type_after_reference_mapping)
        expect(type_before_reference_mapping.dig("properties", "location")).to eq({"type" => "point"})
      end

      it "does not consider `mapping: type` to be a custom mapping type since that is the default for an object" do
        define_point = lambda do |s|
          s.object_type "Point" do |t|
            t.field "x", "Float"
            t.field "y", "Float"
            t.mapping type: "object"
          end
        end

        define_my_type = lambda do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "location", "Point"
            t.index "my_type"
          end
        end

        # We should get the same mapping regardless of which type is defined first.
        type_before_reference_mapping = index_mapping_for "my_type" do |s|
          define_point.call(s)
          define_my_type.call(s)
        end

        type_after_reference_mapping = index_mapping_for "my_type" do |s|
          define_my_type.call(s)
          define_point.call(s)
        end

        expect(type_before_reference_mapping).to eq(type_after_reference_mapping)
        expect(type_before_reference_mapping.dig("properties", "location")).to eq({
          "type" => "object",
          "properties" => {"x" => {"type" => "double"}, "y" => {"type" => "double"}}
        })
      end

      it "merges in any custom mapping options into the underlying generated mapping" do
        define_point = lambda do |s|
          s.object_type "Point" do |t|
            t.field "x", "Float"
            t.field "y", "Float"
            t.mapping meta: {defined_by: "ElasticGraph"}
          end
        end

        define_my_type = lambda do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "location", "Point"
            t.index "my_type"
          end
        end

        # We should get the same mapping regardless of which type is defined first.
        type_before_reference_mapping = index_mapping_for "my_type" do |s|
          define_point.call(s)
          define_my_type.call(s)
        end

        type_after_reference_mapping = index_mapping_for "my_type" do |s|
          define_my_type.call(s)
          define_point.call(s)
        end

        expect(type_before_reference_mapping).to eq(type_after_reference_mapping)
        expect(type_before_reference_mapping.dig("properties", "location")).to eq({
          "properties" => {
            "x" => {"type" => "double"},
            "y" => {"type" => "double"}
          },
          "meta" => {
            "defined_by" => "ElasticGraph"
          }
        })
      end
    end
  end
end
