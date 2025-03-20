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
    RSpec.describe "Datastore config index mappings -- miscellaneous" do
      include_context "IndexMappingsSpecSupport"

      it "puts `dynamic` before `properties` in the returned hash, because it makes the dumped YAML more readable" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.index "my_type"
          end
        end

        # We care about putting `dynamic` before `properties` because this:
        #
        # mappings:
        #   dynamic: strict
        #   properties:
        #     id:
        #       type: keyword
        #     name:
        #       type: keyword
        #     created_at:
        #       type: date
        #       format: strict_date_time
        #     part_ids:
        #       type: keyword
        #
        # ...is more readable than this:
        #
        # mappings:
        #   properties:
        #     id:
        #       type: keyword
        #     name:
        #       type: keyword
        #     created_at:
        #       type: date
        #       format: strict_date_time
        #     part_ids:
        #       type: keyword
        #   dynamic: strict
        #
        # In the latter case, `dynamic: strict` is pushed way down in the YAML file where it's less
        # clear what index it applies to. Since `dynamic: string` is always a one-liner in the YAML
        # while `properties` can have many lines, it's helpful to put `dynamic` first.
        expect(mapping.keys).to eq %w[dynamic properties]
      end

      it "sets `dynamic: strict` on the index to disallow new fields from being created dynamically" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.index "my_type"
          end
        end

        expect(mapping).to include("dynamic" => "strict")
      end

      it "set runtime script which will include the runtime fields" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID" do |f|
              f.runtime_script "example test script"
            end
            t.index "my_type"
          end
        end

        expect(mapping).to include("runtime" => {"id" => {"type" => "keyword", "script" => {"source" => "example test script"}}})
      end

      it "requires an `id` field on every indexed type" do
        expect {
          index_mapping_for "my_type" do |s|
            s.object_type "MyType" do |t|
              t.index "my_type"
            end
          end
        }.to raise_error a_string_including("Field `MyType.id` cannot be resolved, but indexed types must have an `id` field.")
      end

      it "allows the required `id` field to be an indexing-only field, since we require it for indexing but it need not be exposed to GraphQL clients" do
        expect {
          index_mapping_for "my_type" do |s|
            s.object_type "MyType" do |t|
              t.field "id", "ID!", indexing_only: true
              t.index "my_type"
            end
          end
        }.not_to raise_error
      end

      it "includes a `__versions` property (so update scripts can maintain the versions) and a `__sources` property (so that we can filter on present sources)" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.index "my_type"
          end
        end

        expect(mapping.dig("properties")).to include({
          "id" => {"type" => "keyword"},
          "__versions" => {"dynamic" => "false", "type" => "object"},
          "__sources" => {"type" => "keyword"}
        })
      end

      it "keeps `source_from` fields in the mapping so that indexed documents support the field even though it comes from an alternate source" do
        mapping = index_mapping_for "components" do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "name", "String!"

            t.index "widgets"
          end

          s.object_type "Component" do |t|
            t.field "id", "ID!"
            t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

            t.field "widget_name", "String!" do |f|
              f.sourced_from "widget", "name"
            end

            t.index "components"
          end
        end

        expect(mapping.fetch("properties")).to include(
          "widget_name" => {"type" => "keyword"}
        )
      end

      it "can generate a simple mapping for a type with only primitives (of each built-in GraphQL scalar type)" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.field "color", "[Int!]"
            t.field "name", "String!"
            t.field "is_happy", "Boolean"
            t.field "dimension", "[Float!]"
            t.index "my_type"
          end
        end

        expect(mapping.dig("properties")).to include({
          "id" => {"type" => "keyword"},
          "color" => {"type" => "integer"},
          "name" => {"type" => "keyword"},
          "is_happy" => {"type" => "boolean"},
          "dimension" => {"type" => "double"}
        })
      end

      it "respects the configured `name_in_index`" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "Options" do |t|
            t.field "size", "String!"
          end

          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "name", "String!", name_in_index: "name2"
            t.field "options", "Options!", name_in_index: "options2"
            t.index "my_type"
          end
        end

        expect(mapping.dig("properties")).to include({
          "id" => {"type" => "keyword"},
          "name2" => {"type" => "keyword"},
          "options2" => {
            "properties" => {
              "size" => {"type" => "keyword"}
            }
          }
        })
      end

      it "does not allow a `name_in_index` to be a path to a child field unless it is `graphql_only: true` since we have not yet made the indexing side work for that" do
        generate_mapping = lambda do |**field_options|
          index_mapping_for "my_type" do |s|
            s.object_type "Options" do |t|
              t.field "size", "String!"
            end

            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "size", "String!", name_in_index: "options.size", **field_options
              t.field "options", "Options!"
              t.index "my_type"
            end
          end
        end

        expect(&generate_mapping).to raise_error Errors::SchemaError, a_string_including(
          "MyType.size: String!", "invalid `name_in_index`", "Only `graphql_only: true`"
        )

        mapping = generate_mapping.call(graphql_only: true)

        # Verify that it does not have a property for `size` or `options.size`
        expect(mapping.fetch("properties").keys).to contain_exactly("id", "options", "__sources", "__versions")
        expect(mapping.fetch("properties")).to include({
          "id" => {"type" => "keyword"},
          "options" => {
            "properties" => {
              "size" => {"type" => "keyword"}
            }
          }
        })
      end

      it "supports the datastore `geo_point` type via a GraphQL `GeoLocation` type" do
        mapping = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "location", "GeoLocation"
            t.index "my_type"
          end
        end

        expect(mapping.dig("properties", "location")).to eq({"type" => "geo_point"})
      end

      it "includes `{ _routing: { required: true } }` in the mapping if index is using custom shard routing" do
        mapping_with_routing = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.field "name", "String!"
            t.index "my_type" do |i|
              i.route_with "name"
            end
          end
        end

        mapping_without_routing = index_mapping_for "my_type" do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.field "name", "String!"
            t.index "my_type"
          end
        end

        expect(mapping_with_routing).to include({"_routing" => {"required" => true}})
        expect(mapping_without_routing.keys).to exclude("_routing")
      end

      it "includes `{ _size: { enabled: true } }` in the mapping if `index_document_sizes` is set to true" do
        mapping_with_sizes = index_mapping_for "my_type", index_document_sizes: true do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.index "my_type"
          end
        end

        mapping_without_sizes = index_mapping_for "my_type", index_document_sizes: false do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID"
            t.index "my_type"
          end
        end

        expect(mapping_with_sizes).to include({"_size" => {"enabled" => true}})
        expect(mapping_without_sizes.keys).to exclude("_size")
      end

      it "returns a simple mapping for a type with enums" do
        mapping = index_mapping_for "widgets" do |s|
          s.enum_type "Color" do |t|
            t.values "RED", "BLUE", "GREEN"
          end

          s.enum_type "Size" do |t|
            t.values "SMALL", "MEDIUM", "LARGE"
          end

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "amount_cents", "Int!"
            t.field "name", "String!"
            t.field "size", "Size"
            t.field "color", "Color"
            t.index "widgets"
          end
        end

        expect(mapping.dig("properties")).to include({
          "id" => {"type" => "keyword"},
          "amount_cents" => {"type" => "integer"},
          "name" => {"type" => "keyword"},
          "size" => {"type" => "keyword"},
          "color" => {"type" => "keyword"}
        })
      end

      it "returns a mapping for a type with embedded objects" do
        mapping = index_mapping_for "widgets" do |s|
          s.object_type "Color" do |t|
            t.field "red", "Int!"
            t.field "green", "Int!"
            t.field "blue", "Int!"
          end

          s.enum_type "Size" do |t|
            t.values "SMALL", "MEDIUM", "LARGE"
          end

          s.object_type "WidgetOptions" do |t|
            t.field "size", "Size"
            t.field "color", "String!"
            t.field "color_breakdown", "Color!"
          end

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "amount_cents", "Int!"
            t.field "name", "String!"
            t.field "options", "WidgetOptions"
            t.index "widgets"
          end
        end

        expect(mapping.dig("properties", "options")).to eq({
          "properties" => {
            "size" => {"type" => "keyword"},
            "color" => {"type" => "keyword"},
            "color_breakdown" => {
              "properties" => {
                "red" => {"type" => "integer"},
                "green" => {"type" => "integer"},
                "blue" => {"type" => "integer"}
              }
            }
          }
        })
      end

      it "replaces an empty `properties` hash with `type => object` on a nested empty type, since the datastore normalizes it that way" do
        mapping = index_mapping_for "empty" do |s|
          # We need to define `EmptyTypeFilterInput` by hand to avoid schema parsing errors.
          s.raw_sdl "input EmptyTypeFilterInput { foo: Int }"

          s.object_type "EmptyType" do |t|
          end

          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "empty", "EmptyType"
            t.index "empty"
          end
        end

        expect(mapping.dig("properties", "empty")).to eq({"type" => "object"})
      end

      it "does not allow an enum value to be longer than `DEFAULT_MAX_KEYWORD_LENGTH` since we use a `keyword` mapping" do
        expect(index_mapping_for_enum_with_value("A" * DEFAULT_MAX_KEYWORD_LENGTH)).to eq({"type" => "keyword"})

        too_long_value = "A" * (DEFAULT_MAX_KEYWORD_LENGTH + 1)
        expect {
          index_mapping_for_enum_with_value(too_long_value)
        }.to raise_error Errors::SchemaError, a_string_including(
          "Enum value `SomeEnum.#{too_long_value}` is too long: it is #{DEFAULT_MAX_KEYWORD_LENGTH + 1} characters",
          "cannot exceed #{DEFAULT_MAX_KEYWORD_LENGTH} characters"
        )
      end

      def index_mapping_for_enum_with_value(value)
        mapping = index_mapping_for "my_type" do |s|
          s.enum_type "SomeEnum" do |t|
            t.value value
          end

          s.object_type "MyType" do |t|
            t.field "id", "ID!"
            t.field "some_enum", "SomeEnum"
            t.index "my_type"
          end
        end

        mapping.dig("properties", "some_enum")
      end
    end
  end
end
