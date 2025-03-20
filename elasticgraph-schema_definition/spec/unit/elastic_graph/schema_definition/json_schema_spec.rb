# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/errors"
require "elastic_graph/spec_support/schema_definition_helpers"
require "support/json_schema_matcher"

module ElasticGraph
  module SchemaDefinition
    ::RSpec.describe "JSON schema generation" do
      include_context "SchemaDefinitionHelpers"
      json_schema_id = {"allOf" => [{"$ref" => "#/$defs/ID"}, {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}]}
      json_schema_float = {"$ref" => "#/$defs/Float"}
      json_schema_integer = {"$ref" => "#/$defs/Int"}
      json_schema_string = {"allOf" => [{"$ref" => "#/$defs/String"}, {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}]}
      json_schema_null = {"type" => "null"}

      context "on ElasticGraph built-in types, it generates the expected JSON schema" do
        attr_reader :json_schema

        before(:context) do
          @json_schema = dump_schema do |s|
            # Include a random version number to ensure it's getting used correctly
            s.json_schema_version 42

            # Include a basic indexed type here to validate that the envelope is getting
            # generated correctly (we'll ignore it below)
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.index "widgets"
            end
          end
          @tested_types = ::Set.new
        end

        after(:context) do
          built_in_types = @json_schema.fetch("$defs").keys - ["Widget"]
          input_enum_types = %w[DateGroupingGranularityInput DateTimeGroupingGranularityInput DateTimeUnitInput DistanceUnitInput MatchesQueryAllowedEditsPerTerm]

          # Input enum types are named with an `Input` suffix. The JSON schema only contains the types we index, which are output types,
          # and therefore it does not have the input enum types.
          untested_types = built_in_types - @tested_types.to_a - input_enum_types - ["Query"]

          expect(untested_types).to be_empty,
            "It appears that #{untested_types.size} built-in type(s) lack test coverage in `json_schema_spec.rb`. " \
            "Cover them with a test to fix this failure, or ignore this if not running the entire set of built-in type tests:\n\n" \
            "- #{untested_types.sort.join("\n- ")}"
        end

        example "for `#{EVENT_ENVELOPE_JSON_SCHEMA_NAME}`" do
          expect(json_schema).to have_json_schema_like(EVENT_ENVELOPE_JSON_SCHEMA_NAME, {
            "type" => "object",
            "properties" => {
              "op" => {"type" => "string", "enum" => %w[upsert]},
              "type" => {"type" => "string", "enum" => ["Widget"]},
              "id" => {"type" => "string", "maxLength" => DEFAULT_MAX_KEYWORD_LENGTH},
              "version" => {"type" => "integer", "minimum" => 0, "maximum" => (2**63) - 1},
              "record" => {"type" => "object"},
              "latency_timestamps" => {
                "type" => "object",
                "additionalProperties" => false,
                "patternProperties" => {"^\\w+_at$" => {"type" => "string", "format" => "date-time"}}
              },
              JSON_SCHEMA_VERSION_KEY => {"const" => 42},
              "message_id" => {
                "type" => "string",
                "description" => "The optional ID of the message containing this event from whatever messaging system is being used between the publisher and the ElasticGraph indexer."
              }
            },
            "additionalProperties" => false,
            "required" => ["op", "type", "id", "version", JSON_SCHEMA_VERSION_KEY],
            "if" => {"properties" => {"op" => {"const" => "upsert"}}},
            "then" => {"required" => ["record"]}
          }, include_typename: false)
        end

        %w[ID String].each do |type_name|
          example "for `#{type_name}`" do
            expect(json_schema).to have_json_schema_like(type_name, {
              "type" => "string"
            }).which_matches("abc", "a" * DEFAULT_MAX_KEYWORD_LENGTH, "a" * (DEFAULT_MAX_KEYWORD_LENGTH + 1))
              .and_fails_to_match(0, nil, true)
          end
        end

        example "for `Int`" do
          expect(json_schema).to have_json_schema_like("Int", {
            "type" => "integer",
            "minimum" => -2147483648,
            "maximum" => 2147483647
          }).which_matches(0, 1, -1, INT_MAX, INT_MIN)
            .and_fails_to_match("a", 0.5, true, INT_MAX + 1, INT_MIN - 1)
        end

        example "for `Boolean`" do
          expect(json_schema).to have_json_schema_like("Boolean", {
            "type" => "boolean"
          }).which_matches(true, false)
            .and_fails_to_match("true", "false", "yes", "no", 1, 0, nil)
        end

        example "for `Float`" do
          expect(json_schema).to have_json_schema_like("Float", {
            "type" => "number"
          }).which_matches(0, 1, -1, 0.1, -99.0)
            .and_fails_to_match("a", true, nil)
        end

        example "for `TimeZone`" do
          expect(json_schema).to have_json_schema_like("TimeZone", {
            "type" => "string",
            "enum" => GraphQL::ScalarCoercionAdapters::VALID_TIME_ZONES.to_a
          })
            .which_matches("America/Los_Angeles")
            .and_fails_to_match("America/Seattle") # America/Seattle is not a valid time zone.
        end

        example "for `Untyped`" do
          expect(json_schema).to have_json_schema_like("Untyped", {
            "type" => %w[array boolean integer number object string]
          }).which_matches(
            3,
            3.75,
            "string",
            true,
            %w[a b],
            {"some" => "data"},
            {"some" => {"nested" => {"data" => [1, true, "3"]}}}
          ).and_fails_to_match(nil)
        end

        example "for `GeoLocation`" do
          expect(json_schema).to have_json_schema_like("GeoLocation", {
            "type" => "object",
            "properties" => {
              "latitude" => {
                "allOf" => [
                  json_schema_float,
                  {"minimum" => -90, "maximum" => 90}
                ]
              },
              "longitude" => {
                "allOf" => [
                  json_schema_float,
                  {"minimum" => -180, "maximum" => 180}
                ]
              }
            },
            "required" => %w[latitude longitude]
          }).which_matches(
            {"latitude" => 0, "longitude" => 0},
            {"latitude" => -90, "longitude" => -180},
            {"latitude" => 90, "longitude" => 180}
          ).and_fails_to_match(
            nil,
            {},
            {"latitude" => "0", "longitude" => "1"},
            {"latitude" => -91, "longitude" => 0},
            {"latitude" => 91, "longitude" => 0},
            {"latitude" => 0, "longitude" => -181},
            {"latitude" => 0, "longitude" => 181},
            {"latitude" => nil, "longitude" => 0},
            {"latitude" => 0, "longitude" => nil}
          )
        end

        example "for `Cursor`" do
          expect(json_schema).to have_json_schema_like("Cursor", {"type" => "string"})
            .which_matches("abc")
            .and_fails_to_match(0, nil, true)
        end

        example "for `Date`" do
          expect(json_schema).to have_json_schema_like("Date", {"type" => "string", "format" => "date"})
            .which_matches("2023-01-01", "1999-12-31") # yyyy-MM-dd
            .and_fails_to_match(0, nil, true, "01-01-2023", "0000-00-00", "2023-13-40")
        end

        example "for `DateUnit`" do
          expect(json_schema).to have_json_schema_like("DateUnit", {
            "enum" => %w[DAY], "type" => "string"
          }).which_matches(*%w[DAY])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `DateGroupingGranularity`" do
          expect(json_schema).to have_json_schema_like("DateGroupingGranularity", {
            "enum" => %w[YEAR QUARTER MONTH WEEK DAY], "type" => "string"
          }).which_matches(*%w[YEAR QUARTER MONTH WEEK DAY])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `DateGroupingTruncationUnit`" do
          expect(json_schema).to have_json_schema_like("DateGroupingTruncationUnit", {
            "enum" => %w[YEAR QUARTER MONTH WEEK DAY], "type" => "string"
          }).which_matches(*%w[YEAR QUARTER MONTH WEEK DAY])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `DateTime`" do
          expect(json_schema).to have_json_schema_like("DateTime", {
            "type" => "string", "format" => "date-time"
          }).which_matches("2023-01-01T00:00:00.000Z", "1999-12-31T23:59:59.999Z") # T: yyyy-MM-dd'T'HH:mm:ss.SSSZ
            .and_fails_to_match(0, nil, true, "01-01-2023", "0000-00-00 00:00", "2023-13-40 45:33")
        end

        example "for `DateTimeUnit`" do
          expect(json_schema).to have_json_schema_like("DateTimeUnit", {
            "enum" => %w[DAY HOUR MINUTE SECOND MILLISECOND], "type" => "string"
          }).which_matches(*%w[DAY HOUR MINUTE SECOND MILLISECOND])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `DateTimeGroupingGranularity`" do
          expect(json_schema).to have_json_schema_like("DateTimeGroupingGranularity", {
            "enum" => %w[YEAR QUARTER MONTH WEEK DAY HOUR MINUTE SECOND], "type" => "string"
          }).which_matches(*%w[YEAR QUARTER MONTH WEEK DAY HOUR MINUTE SECOND])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `DateTimeGroupingTruncationUnit`" do
          expect(json_schema).to have_json_schema_like("DateTimeGroupingTruncationUnit", {
            "enum" => %w[YEAR QUARTER MONTH WEEK DAY HOUR MINUTE SECOND], "type" => "string"
          }).which_matches(*%w[YEAR QUARTER MONTH WEEK DAY HOUR MINUTE SECOND])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `DayOfWeek`" do
          expect(json_schema).to have_json_schema_like("DayOfWeek", {
            "enum" => %w[MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY SUNDAY], "type" => "string"
          }).which_matches(*%w[MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY SUNDAY])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `DistanceUnit`" do
          expect(json_schema).to have_json_schema_like("DistanceUnit", {
            "enum" => %w[MILE YARD FOOT INCH KILOMETER METER CENTIMETER MILLIMETER NAUTICAL_MILE], "type" => "string"
          }).which_matches(*%w[MILE YARD FOOT INCH KILOMETER METER CENTIMETER MILLIMETER NAUTICAL_MILE])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `JsonSafeLong`" do
          expect(json_schema).to have_json_schema_like("JsonSafeLong", {
            "maximum" => JSON_SAFE_LONG_MAX,
            "minimum" => JSON_SAFE_LONG_MIN,
            "type" => "integer"
          }).which_matches(0, JSON_SAFE_LONG_MIN, JSON_SAFE_LONG_MAX)
            .and_fails_to_match(0.5, nil, true, JSON_SAFE_LONG_MAX + 1, JSON_SAFE_LONG_MIN - 1)
        end

        example "for `LocalTime`" do
          expect(json_schema).to have_json_schema_like("LocalTime", {
            "type" => "string",
            "pattern" => VALID_LOCAL_TIME_JSON_SCHEMA_PATTERN
          })
            .which_matches("01:23:45", "14:56:39.000", "23:59:01.1", "23:59:01.12", "23:59:01.13") # HH:mm:ss, HH:mm:ss.S, HH:mm:ss.SS, HH:mm:ss.SSS
            .and_fails_to_match(0, nil, true, "abc", "99:00:00", "59:59.999Z", "01:23:45.1234", "14:56:39a000")
        end

        example "for `LocalTimeUnit`" do
          expect(json_schema).to have_json_schema_like("LocalTimeUnit", {
            "enum" => %w[HOUR MINUTE SECOND MILLISECOND], "type" => "string"
          }).which_matches(*%w[HOUR MINUTE SECOND MILLISECOND])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `LocalTimeGroupingTruncationUnit`" do
          expect(json_schema).to have_json_schema_like("LocalTimeGroupingTruncationUnit", {
            "enum" => %w[HOUR MINUTE SECOND], "type" => "string"
          }).which_matches(*%w[HOUR MINUTE SECOND])
            .and_fails_to_match(0, nil, true, "literally any other string")
        end

        example "for `LongString`" do
          expect(json_schema).to have_json_schema_like("LongString", {
            "maximum" => LONG_STRING_MAX,
            "minimum" => LONG_STRING_MIN,
            "type" => "integer"
          })
            .which_matches(0, LONG_STRING_MAX, LONG_STRING_MIN)
            .and_fails_to_match(0.5, nil, true, LONG_STRING_MIN - 1, LONG_STRING_MAX + 1)
        end

        it "excludes `Query`" do
          expect(json_schema.fetch("$defs").keys).to exclude "Query"
        end

        def have_json_schema_like(type_name, *args, **kwargs)
          @tested_types << type_name
          super(type_name, *args, **kwargs)
        end
      end

      it "allows any valid JSON type for a nullable `Untyped` field" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "j1", "Untyped"
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "j1" => json_schema_ref("Untyped", is_keyword_type: true)
          },
          "required" => %w[j1]
        }).which_matches(
          {"j1" => 3},
          {"j1" => 3.75},
          {"j1" => "string"},
          {"j1" => "a" * DEFAULT_MAX_KEYWORD_LENGTH},
          {"j1" => nil},
          {"j1" => true},
          {"j1" => %w[a b]},
          {"j1" => {"some" => "data"}},
          {"j1" => {"some" => {"nested" => {"data" => [1, true, "3"]}}}}
        ).and_fails_to_match(
          {"j1" => "a" * (DEFAULT_MAX_KEYWORD_LENGTH + 1)}
        )
      end

      it "does not duplicate `required` fields when 2 GraphQL fields are both backed by the same indexing field" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "name", "String!"
            t.field "name2", "String!", name_in_index: "name", graphql_only: true
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "name" => json_schema_ref("String!")
          },
          "required" => %w[name]
        })
      end

      it "does not allow multiple indexing fields with the same name because that would result in multiple JSON schema fields flowing into the same index field but with conflicting values" do
        expect {
          dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "name", "String!"
              t.field "name2", "String!", name_in_index: "name"
            end
          end
        }.to raise_error Errors::SchemaError, a_string_including("Duplicate indexing field", "MyType: name", "set `graphql_only: true`")
      end

      it "raises an exception when `json_schema` on a field definition has invalid json schema option values" do
        dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "foo", "String" do |f|
              expect {
                f.json_schema maxLength: "twelve"
              }.to raise_error Errors::SchemaError, a_string_including("Invalid JSON schema options", "foo: String", "maxLength")

              expect(f.json_schema_options).to be_empty

              # Demonstrate that `maxLength` with an int value is allowed
              f.json_schema maxLength: 12
            end
          end
        end
      end

      it "does not allow the extra `ElasticGraph` metadata that ElasticGraph adds itself" do
        dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "foo", "String" do |f|
              expect {
                f.json_schema ElasticGraph: {type: "String"}
              }.to raise_error Errors::SchemaError, a_string_including("Invalid JSON schema options", "foo: String", '"data_pointer": "/ElasticGraph"')

              expect(f.json_schema_options).to be_empty

              # Demonstrate that `maxLength` with an int value is allowed
              f.json_schema maxLength: 12
            end
          end
        end
      end

      it "raises an exception when `json_schema` on a field definition has invalid json schema option names" do
        dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "foo", "String" do |f|
              expect {
                f.json_schema longestLength: 14 # maxLength is correct, not longestLength
              }.to raise_error Errors::SchemaError, a_string_including("Invalid JSON schema options", "foo: String", "longestLength")
            end
          end
        end
      end

      it "raises an exception when `json_schema` on a scalar type has invalid json schema option values" do
        dump_schema do |s|
          s.scalar_type "MyType" do |t|
            t.mapping type: "keyword"

            expect {
              t.json_schema type: "string", maxLength: "twelve"
            }.to raise_error Errors::SchemaError, a_string_including("Invalid JSON schema options", "MyType", "twelve")

            # Demonstrate that `maxLength` with an int value is allowed
            t.json_schema type: "string", maxLength: 12
          end
        end
      end

      it "raises an exception when `json_schema` on a scalar type has invalid json schema option values" do
        dump_schema do |s|
          s.scalar_type "MyType" do |t|
            t.mapping type: "keyword"

            expect {
              t.json_schema type: "string", longestLength: 14 # maxLength is correct, not longestLength
            }.to raise_error Errors::SchemaError, a_string_including("Invalid JSON schema options", "MyType", "longestLength")

            t.json_schema type: "string"
          end
        end
      end

      it "raises an exception when `json_schema` on an object type has invalid json schema option values" do
        dump_schema do |s|
          s.object_type "MyType" do |t|
            expect {
              t.json_schema type: "string", maxLength: "twelve"
            }.to raise_error Errors::SchemaError, a_string_including("Invalid JSON schema options", "MyType", "twelve")

            # Demonstrate that `maxLength` with an int value is allowed
            t.json_schema type: "string", maxLength: 12
          end
        end
      end

      it "raises an exception when `json_schema` on a scalar type has invalid json schema option values" do
        dump_schema do |s|
          s.object_type "MyType" do |t|
            t.mapping type: "keyword"

            expect {
              t.json_schema type: "string", longestLength: 14 # maxLength is correct, not longestLength
            }.to raise_error Errors::SchemaError, a_string_including("Invalid JSON schema options", "MyType", "longestLength")
          end
        end
      end

      context "for a field that is `sourced_from` a related type" do
        it "excludes the `source_from` field because it comes from another source type and will be represented in the JSON schema of that type" do
          json_schema = dump_schema do |s|
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

          expect(json_schema).to have_json_schema_like("Component", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!")
            },
            "required" => %w[id]
          })
        end

        it "does not allow any JSON schema customizations of the field because they should be configured on the source type itself" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "size", "Int"

                t.index "widgets"
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                t.relates_to_one "widget", "Widget", via: "component_ids", dir: :in

                # Here we call `json_schema` after `sourced_from`...
                t.field "widget_name", "String!" do |f|
                  f.sourced_from "widget", "name"
                  f.json_schema minLength: 4
                end

                # ...vs here we call it before. We do this to demonstrate the order doesn't matter.
                t.field "widget_size", "Int" do |f|
                  f.json_schema minimum: 0
                  f.sourced_from "widget", "size"
                end

                t.index "components"
              end
            end
          }.to raise_error a_string_including(
            "Component` has 2 field(s) (`widget_name`, `widget_size`)",
            "also have JSON schema customizations"
          )
        end
      end

      %w[ID String].first(1).each do |graphql_type|
        it "limits the length of `#{graphql_type}!` fields based on datastore limits" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "foo", "#{graphql_type}!"
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "foo" => {
                "allOf" => [
                  {"$ref" => "#/$defs/#{graphql_type}"},
                  {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
                ]
              }
            },
            "required" => %w[foo]
          }).which_matches(
            {"foo" => "abc"},
            {"foo" => "a" * DEFAULT_MAX_KEYWORD_LENGTH}
          ).and_fails_to_match(
            {"foo" => "a" * (DEFAULT_MAX_KEYWORD_LENGTH + 1)},
            {"foo" => nil},
            {"foo" => -129},
            {"foo" => 128}
          )
        end

        it "limits the length of `#{graphql_type}` fields based on datastore limits" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "foo", graphql_type
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "foo" => {
                "anyOf" => [
                  {
                    "allOf" => [
                      {"$ref" => "#/$defs/#{graphql_type}"},
                      {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
                    ]
                  },
                  {"type" => "null"}
                ]
              }
            },
            "required" => %w[foo]
          }).which_matches(
            {"foo" => "abc"},
            {"foo" => nil},
            {"foo" => "a" * DEFAULT_MAX_KEYWORD_LENGTH}
          ).and_fails_to_match(
            {"foo" => "a" * (DEFAULT_MAX_KEYWORD_LENGTH + 1)},
            {"foo" => -129},
            {"foo" => 128}
          )
        end

        it "uses a larger `maxLength` for a #{graphql_type} if the mapping type is set to `text`" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "foo", "#{graphql_type}!" do |f|
                f.mapping type: "text"
              end
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "foo" => {
                "allOf" => [
                  {"$ref" => "#/$defs/#{graphql_type}"},
                  {"maxLength" => DEFAULT_MAX_TEXT_LENGTH}
                ]
              }
            },
            "required" => %w[foo]
          }).which_matches(
            {"foo" => "abc"},
            {"foo" => "a" * DEFAULT_MAX_TEXT_LENGTH}
          ).and_fails_to_match(
            {"foo" => "a" * (DEFAULT_MAX_TEXT_LENGTH + 1)},
            {"foo" => nil},
            {"foo" => -129},
            {"foo" => 128}
          )
        end
      end

      it "limits the size of custom `keyword` types based on datastore limits" do
        json_schema = dump_schema do |s|
          s.scalar_type "MyString" do |t|
            t.json_schema type: "string"
            t.mapping type: "keyword"
          end

          s.object_type "MyType" do |t|
            t.field "foo", "MyString"
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "foo" => {
              "anyOf" => [
                {
                  "allOf" => [
                    {"$ref" => "#/$defs/MyString"},
                    {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
                  ]
                },
                {"type" => "null"}
              ]
            }
          },
          "required" => %w[foo]
        }).which_matches(
          {"foo" => "abc"},
          {"foo" => nil},
          {"foo" => "a" * DEFAULT_MAX_KEYWORD_LENGTH}
        ).and_fails_to_match(
          {"foo" => "a" * (DEFAULT_MAX_KEYWORD_LENGTH + 1)},
          {"foo" => -129},
          {"foo" => 128}
        )
      end

      it "allows the `maxLength` to be overridden on keyword and text fields" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!" do |f|
              f.json_schema maxLength: 50
            end

            t.field "string", "String!" do |f|
              f.json_schema maxLength: 100
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "id" => {
              "allOf" => [
                {"$ref" => "#/$defs/ID"},
                {"maxLength" => 50}
              ]
            },
            "string" => {
              "allOf" => [
                {"$ref" => "#/$defs/String"},
                {"maxLength" => 100}
              ]
            }
          },
          "required" => %w[id string]
        })
      end

      it "does not include `maxLength` on enum fields since we already limit the values" do
        json_schema = dump_schema do |s|
          s.enum_type "Color" do |t|
            t.value "RED"
            t.value "GREEN"
            t.value "BLUE"
          end

          s.object_type "MyType" do |t|
            t.field "color1", "Color!"

            t.field "color2", "Color!" do |f|
              f.json_schema maxLength: 50
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "color1" => {"$ref" => "#/$defs/Color"},
            "color2" => {"$ref" => "#/$defs/Color"}
          },
          "required" => %w[color1 color2]
        }).which_matches(
          {"color1" => "RED", "color2" => "GREEN"},
          {"color1" => "BLUE", "color2" => "RED"}
        ).and_fails_to_match(
          {"color1" => "YELLOW", "color2" => "GREEN"},
          {"color1" => "BLUE", "color2" => "BROWN"}
        )
      end

      it "limits byte types based on the datastore mapping type range" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "byte", "Int!" do |f|
              f.mapping type: "byte"
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "byte" => {
              "allOf" => [
                json_schema_integer,
                {"minimum" => -128, "maximum" => 127}
              ]
            }
          },
          "required" => %w[byte]
        }).which_matches(
          {"byte" => 0},
          {"byte" => -128},
          {"byte" => 127}
        ).and_fails_to_match(
          {"byte" => "a"},
          {"byte" => nil},
          {"byte" => -129},
          {"byte" => 128}
        )
      end

      it "limits short types based on the datastore mapping type range" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "short", "Int!" do |f|
              f.mapping type: "short"
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "short" => {
              "allOf" => [
                json_schema_integer,
                {"minimum" => -32_768, "maximum" => 32_767}
              ]
            }
          },
          "required" => %w[short]
        }).which_matches(
          {"short" => 0},
          {"short" => -32_768},
          {"short" => 32_767}
        ).and_fails_to_match(
          {"short" => "a"},
          {"short" => nil},
          {"short" => -32_769},
          {"short" => 32_768}
        )
      end

      it "limits integer types based on the datastore mapping type range" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "integer", "Int!" do |f|
              f.mapping type: "integer"
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "integer" => json_schema_ref("Int!")
          },
          "required" => %w[integer]
        }).which_matches(
          {"integer" => 0},
          {"integer" => INT_MAX},
          {"integer" => INT_MIN}
        ).and_fails_to_match(
          {"integer" => "a"},
          {"integer" => nil},
          {"integer" => INT_MAX + 1},
          {"integer" => INT_MIN - 1}
        )
      end

      it "supports nullable fields by wrapping the schema in 'anyOf' with a 'null' type" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "is_happy", "Boolean"
            t.field "size", "Float"
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "is_happy" => json_schema_ref("Boolean"),
            "size" => json_schema_ref("Float")
          },
          "required" => %w[is_happy size]
        })
      end

      it "returns a JSON schema for a type with arrays" do
        json_schema = dump_schema do |s|
          s.object_type "Widget" do |t|
            t.field "color", "[String!]"
            t.field "amount_cents", "[Int!]!"
          end
        end

        expect(json_schema).to have_json_schema_like("Widget", {
          "type" => "object",
          "properties" => {
            "color" => {
              "anyOf" => [
                {
                  "type" => "array",
                  "items" => json_schema_string
                },
                json_schema_null
              ]
            },
            "amount_cents" => {
              "type" => "array",
              "items" => json_schema_integer
            }
          },
          "required" => %w[color amount_cents]
        })
      end

      it "returns a JSON schema for a type with enums" do
        json_schema = dump_schema do |s|
          s.enum_type "Color" do |t|
            t.values "RED", "BLUE", "GREEN"
          end

          s.enum_type "Size" do |t|
            t.values "SMALL", "MEDIUM", "LARGE"
          end

          s.object_type "Widget" do |t|
            t.field "size", "Size!"
            t.field "color", "Color"
          end
        end

        expect(json_schema).to have_json_schema_like("Size", {
          "type" => "string",
          "enum" => %w[SMALL MEDIUM LARGE]
        })

        expect(json_schema).to have_json_schema_like("Color", {
          "type" => "string",
          "enum" => %w[RED BLUE GREEN]
        })

        expect(json_schema).to have_json_schema_like("Widget", {
          "type" => "object",
          "properties" => {
            "size" => json_schema_ref("Size!"),
            "color" => json_schema_ref("Color")
          },
          "required" => %w[size color]
        })
      end

      it "respects enum value overrides" do
        json_schema = dump_schema(enum_value_overrides_by_type: {
          Color: {RED: "REDISH", BLUE: "BLUEISH"}
        }) do |s|
          s.enum_type "Color" do |t|
            t.values "RED", "BLUE", "GREEN"
          end
        end

        expect(json_schema).to have_json_schema_like("Color", {
          "type" => "string",
          "enum" => %w[REDISH BLUEISH GREEN]
        })
      end

      it "uses `enum` for an Enum with a single value" do
        json_schema = dump_schema do |s|
          s.enum_type "Color" do |t|
            t.values "RED"
          end
        end

        expect(json_schema).to have_json_schema_like("Color", {
          "type" => "string",
          "enum" => ["RED"]
        })
      end

      it "returns a JSON schema for a type with objects" do
        json_schema = dump_schema do |s|
          s.object_type "Color" do |t|
            t.field "red", "Int!"
            t.field "green", "Int!"
            t.field "blue", "Int!"
          end

          s.object_type "WidgetOptions" do |t|
            t.field "color", "String!"
            t.field "color_breakdown", "Color!"
          end

          s.object_type "Widget" do |t|
            t.field "options", "WidgetOptions"
          end
        end

        expect(json_schema).to have_json_schema_like("Color", {
          "type" => "object",
          "properties" => {
            "red" => json_schema_ref("Int!"),
            "green" => json_schema_ref("Int!"),
            "blue" => json_schema_ref("Int!")
          },
          "required" => %w[red green blue]
        })

        expect(json_schema).to have_json_schema_like("WidgetOptions", {
          "type" => "object",
          "properties" => {
            "color" => json_schema_ref("String!"),
            "color_breakdown" => json_schema_ref("Color!")
          },
          "required" => %w[color color_breakdown]
        })

        expect(json_schema).to have_json_schema_like("Widget", {
          "type" => "object",
          "properties" => {
            "options" => json_schema_ref("WidgetOptions")
          },
          "required" => %w[options]
        })
      end

      it "returns a JSON schema with definitions for custom scalar types" do
        json_schema = dump_schema do |s|
          s.scalar_type "PhoneNumber" do |t|
            t.mapping type: "keyword"
            t.json_schema type: "string", format: "^\\+[1-9][0-9]{1,14}$"
          end
        end

        expect(json_schema).to have_json_schema_like("PhoneNumber", {
          "type" => "string",
          "format" => "^\\+[1-9][0-9]{1,14}$"
        })
      end

      it "returns a JSON schema for a type with wrapped enums" do
        json_schema = dump_schema do |s|
          s.enum_type "Size" do |t|
            t.values "SMALL", "MEDIUM", "LARGE"
          end

          s.object_type "Widget" do |t|
            t.field "null_array_null", "[Size]"
            t.field "non_null_array_null", "[Size]!"
            t.field "null_array_non_null", "[Size!]"
            t.field "non_null_array_non_null", "[Size!]!"
            t.field "null_null_array_null", "[[Size]]"
          end
        end

        expect(json_schema).to have_json_schema_like("Widget", {
          "type" => "object",
          "properties" => {
            "null_array_null" => {
              "anyOf" => [
                {
                  "type" => "array",
                  "items" => json_schema_ref("Size")
                },
                json_schema_null
              ]
            },
            "non_null_array_null" => {
              "type" => "array",
              "items" => json_schema_ref("Size")
            },
            "null_array_non_null" => {
              "anyOf" => [
                {
                  "type" => "array",
                  "items" => json_schema_ref("Size!")
                },
                json_schema_null
              ]
            },
            "non_null_array_non_null" => {
              "type" => "array",
              "items" => json_schema_ref("Size!")
            },
            "null_null_array_null" => {
              "anyOf" => [
                {
                  "type" => "array",
                  "items" => {
                    "anyOf" => [
                      {
                        "type" => "array",
                        "items" => json_schema_ref("Size")
                      },
                      json_schema_null
                    ]
                  }
                },
                json_schema_null
              ]
            }
          },
          "required" => %w[null_array_null non_null_array_null null_array_non_null non_null_array_non_null null_null_array_null]
        })
      end

      it "returns a JSON schema for a type with wrapped objects" do
        json_schema = dump_schema do |s|
          s.object_type "Color" do |t|
            t.field "red", "Int!"
            t.field "green", "Int!"
            t.field "blue", "Int!"
          end

          s.object_type "WidgetOptions" do |t|
            t.field "color_breakdown", "Color!"
          end

          s.object_type "Widget" do |t|
            t.field "nullable", "WidgetOptions"
            t.field "non_null", "WidgetOptions!"
            t.field "null_array_null", "[WidgetOptions]" do |f|
              f.mapping type: "object"
            end
            t.field "non_null_array_null", "[WidgetOptions]!" do |f|
              f.mapping type: "object"
            end
            t.field "null_array_non_null", "[WidgetOptions!]" do |f|
              f.mapping type: "object"
            end
            t.field "non_null_array_non_null", "[WidgetOptions!]!" do |f|
              f.mapping type: "object"
            end
            t.field "null_null_array_null", "[[WidgetOptions]]" do |f|
              f.mapping type: "object"
            end
          end
        end

        expect(json_schema).to have_json_schema_like("Widget", {
          "type" => "object",
          "properties" => {
            "nullable" => json_schema_ref("WidgetOptions"),
            "non_null" => json_schema_ref("WidgetOptions!"),
            "null_array_null" => {
              "anyOf" => [
                {
                  "type" => "array",
                  "items" => {
                    "anyOf" => [
                      {"$ref" => "#/$defs/WidgetOptions"},
                      json_schema_null
                    ]
                  }
                },
                json_schema_null
              ]
            },
            "non_null_array_null" => {
              "type" => "array",
              "items" => {
                "anyOf" => [
                  {"$ref" => "#/$defs/WidgetOptions"},
                  json_schema_null
                ]
              }
            },
            "null_array_non_null" => {
              "anyOf" => [
                {
                  "type" => "array",
                  "items" => {"$ref" => "#/$defs/WidgetOptions"}
                },
                json_schema_null
              ]
            },
            "non_null_array_non_null" => {
              "type" => "array",
              "items" => {
                "$ref" => "#/$defs/WidgetOptions"
              }
            },
            "null_null_array_null" => {
              "anyOf" => [
                {
                  "type" => "array",
                  "items" => {
                    "anyOf" => [
                      {
                        "type" => "array",
                        "items" => {
                          "anyOf" => [
                            {"$ref" => "#/$defs/WidgetOptions"},
                            json_schema_null
                          ]
                        }
                      },
                      json_schema_null
                    ]
                  }
                },
                json_schema_null
              ]
            }
          },
          "required" => %w[nullable non_null null_array_null non_null_array_null null_array_non_null non_null_array_non_null null_null_array_null]
        })
      end

      context "on an indexed type with a rollover index" do
        it "makes the JSON schema for a rollover index timestamp field on the indexed type non-nullable since a target index cannot be chosen without it" do
          json_schema = dump_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime"
              t.index "widgets" do |i|
                i.rollover :monthly, "created_at"
              end
            end
          end

          expect(json_schema).to have_json_schema_like("Widget", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!"),
              "created_at" => json_schema_ref("DateTime!")
            },
            "required" => %w[id created_at]
          })

          expect(json_schema).to have_json_schema_like("DateTime", {
            "type" => "string",
            "format" => "date-time"
          })
        end

        it "does not break other configured JSON schema customizations when forcing the non-nullability on a rollover timestamp field" do
          json_schema = dump_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime" do |f|
                f.json_schema pattern: "\w+"
              end
              t.index "widgets" do |i|
                i.rollover :monthly, "created_at"
              end
            end
          end

          expect(json_schema).to have_json_schema_like("Widget", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!"),
              "created_at" => {
                "allOf" => [
                  {"$ref" => "#/$defs/DateTime"},
                  {"pattern" => "\w+"}
                ]
              }
            },
            "required" => %w[id created_at]
          })

          expect(json_schema).to have_json_schema_like("DateTime", {
            "type" => "string",
            "format" => "date-time"
          })
        end

        it "supports nested timestamp fields, applying non-nullability to every field in the path" do
          json_schema = dump_schema do |s|
            s.object_type "WidgetTimestamps" do |t|
              t.field "created_at", "DateTime"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "timestamps", "WidgetTimestamps"
              t.index "widgets" do |i|
                i.rollover :monthly, "timestamps.created_at"
              end
            end
          end

          expect(json_schema).to have_json_schema_like("Widget", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!"),
              "timestamps" => json_schema_ref("WidgetTimestamps!")
            },
            "required" => %w[id timestamps]
          })

          expect(json_schema).to have_json_schema_like("WidgetTimestamps", {
            "type" => "object",
            "properties" => {
              "created_at" => json_schema_ref("DateTime!")
            },
            "required" => %w[created_at]
          })

          expect(json_schema).to have_json_schema_like("DateTime", {
            "type" => "string",
            "format" => "date-time"
          })
        end

        it "raises an error if the timestamp field specified in `rollover` is absent from the index" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("Field `Widget.created_at` cannot be resolved, but it is referenced as an index `rollover` field."))
        end

        it "allows the timestamp field to be an indexing-only field since it need not be exposed to GraphQL clients" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_at", "DateTime", indexing_only: true
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end
          }.not_to raise_error
        end

        it "allows the timestamp field to be a `DateTime` or `Date` field" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_on", "Date"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_on"
                end
              end
            end
          }.not_to raise_error

          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_at", "DateTime"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end
          }.not_to raise_error
        end

        it "allows the timestamp field to be a non-nullable field" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_on", "Date!"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_on"
                end
              end
            end
          }.not_to raise_error

          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_at", "DateTime!"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end
          }.not_to raise_error
        end

        it "raises an error if a nested rollover timestamp field references an undefined type" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "options", "WidgetOptions"
                t.index "widgets" do |i|
                  i.rollover :monthly, "options.created_at"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Field `Widget.options.created_at` cannot be resolved",
            "Verify that all fields and types referenced by `options.created_at` are defined."
          ))
        end

        it "raises an error if a rollover timestamp field references an object type" do
          expect {
            dump_schema do |s|
              s.object_type "WidgetOpts" do |t|
                t.field "size", "Int"
              end

              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "opts", "WidgetOpts"
                t.index "widgets" do |i|
                  i.rollover :monthly, "opts"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("rollover field `Widget.opts: WidgetOpts` cannot be used for rollover since it is not a `Date` or `DateTime` field"))
        end

        it "raises an error if a rollover timestamp field references an enum type" do
          expect {
            dump_schema do |s|
              s.enum_type "Color" do |t|
                t.values "RED", "GREEN", "BLUE"
              end

              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "color", "Color"
                t.index "widgets" do |i|
                  i.rollover :monthly, "color"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("rollover field `Widget.color: Color` cannot be used for rollover since it is not a `Date` or `DateTime` field"))
        end

        it "raises an error if a rollover timestamp field references an scalar type that can't be used for rollover" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_at", "String" # not a DateTime!
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("rollover field `Widget.created_at: String` cannot be used for rollover since it is not a `Date` or `DateTime` field"))
        end

        it "respects configured type name overrides when determining if a rollover field is a valid type" do
          expect {
            dump_schema(type_name_overrides: {"Date" => "Etad", "DateTime" => "EmitEtad"}) do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_at", "EmitEtad"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end
              end

              s.object_type "Component" do |t|
                t.field "id", "ID"
                t.field "created_on", "Etad"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_on"
                end
              end

              s.object_type "Part" do |t|
                t.field "id", "ID"
                t.field "created_at", "String"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "rollover field `Part.created_at: String` cannot be used for rollover since it is not a `Etad` or `EmitEtad` field"
          ))
        end

        it "raises an error if a rollover timestamp field references a list field" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_ats", "[DateTime]"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_ats"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("rollover field `Widget.created_ats: [DateTime]` cannot be used for rollover since it is a list field."))

          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "created_ons", "[Date]"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_ons"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("rollover field `Widget.created_ons: [Date]` cannot be used for rollover since it is a list field."))
        end

        it "allows the timestamp field specified in `rollover` to be defined after the `index` call" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.index "widgets" do |i|
                  i.rollover :monthly, "created_at"
                end

                t.field "created_at", "DateTime"
              end
            end
          }.not_to raise_error
        end
      end

      context "on an indexed type with custom shard routing" do
        it "makes the custom routing field non-nullable in the JSON schema since we cannot target a shard without it" do
          json_schema = dump_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "user_id", "ID"

              t.index "widgets" do |i|
                i.route_with "user_id"
              end
            end
          end

          expect(json_schema).to have_json_schema_like("ID", {
            "type" => "string"
          })

          expect(json_schema).to have_json_schema_like("Widget", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!"),
              "user_id" => shard_routing_string_field
            },
            "required" => %w[id user_id]
          }).which_matches(
            {"id" => "abc", "user_id" => "def"},
            {"id" => "abc", "user_id" => " d"},
            {"id" => "abc", "user_id" => "\td"},
            {"id" => "abc", "user_id" => "d\n"}
          ).and_fails_to_match(
            {"id" => "abc", "user_id" => nil},
            {"id" => "abc", "user_id" => ""},
            {"id" => "abc", "user_id" => "  "},
            {"id" => "abc", "user_id" => " \t"},
            {"id" => "abc", "user_id" => " \n"}
          )
        end

        it "supports nested routing fields, applying non-nullability to every field in the path" do
          json_schema = dump_schema do |s|
            s.object_type "WidgetIDs" do |t|
              t.field "user_id", "ID"
            end

            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "widget_ids", "WidgetIDs"
              t.index "widgets" do |i|
                i.route_with "widget_ids.user_id"
              end
            end
          end

          expect(json_schema).to have_json_schema_like("WidgetIDs", {
            "type" => "object",
            "properties" => {
              "user_id" => shard_routing_string_field
            },
            "required" => ["user_id"]
          })

          expect(json_schema).to have_json_schema_like("Widget", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!"),
              "widget_ids" => json_schema_ref("WidgetIDs!")
            },
            "required" => %w[id widget_ids]
          })
        end

        it "raises an error if the specified custom shard routing field is absent from the index" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.index "widgets" do |i|
                  i.route_with "user_id"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("Field `Widget.user_id` cannot be resolved, but it is referenced as an index `route_with` field."))
        end

        it "raises an error if a shard routing field references an object type" do
          expect {
            dump_schema do |s|
              s.object_type "WidgetOpts" do |t|
                t.field "size", "Int"
              end

              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "opts", "WidgetOpts"
                t.index "widgets" do |i|
                  i.route_with "opts"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("shard routing field `Widget.opts: WidgetOpts` cannot be used for routing since it is not a leaf field."))
        end

        it "raises an error if a shard routing field references a list field" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "tags", "[String]"
                t.index "widgets" do |i|
                  i.route_with "tags"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("shard routing field `Widget.tags: [String]` cannot be used for routing since it is not a leaf field."))
        end

        it "allows the custom shard routing field to be an indexing-only field since it need not be exposed to GraphQL clients" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "user_id", "ID", indexing_only: true
                t.index "widgets" do |i|
                  i.route_with "user_id"
                end
              end
            end
          }.not_to raise_error
        end

        it "raises an error if a nested custom shard routing field references an undefined type" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "options", "WidgetOptions"
                t.index "widgets" do |i|
                  i.route_with "options.user_id"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including(
            "Field `Widget.options.user_id` cannot be resolved",
            "Verify that all fields and types referenced by `options.user_id` are defined"
          ))
        end

        it "allows the custom shard routing field to be nullable or non-null" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "user_id", "ID"
                t.index "widgets" do |i|
                  i.route_with "user_id"
                end
              end
            end
          }.not_to raise_error

          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "user_id", "ID!"
                t.index "widgets" do |i|
                  i.route_with "user_id"
                end
              end
            end
          }.not_to raise_error
        end

        it "allows the specified custom shard routing field to be defined after `index`" do
          expect {
            dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.index "widgets" do |i|
                  i.route_with "user_id"
                end

                t.field "user_id", "ID"
              end
            end
          }.not_to raise_error
        end

        it "mentions the expected field in the error message when dealing with nested fields" do
          expect {
            dump_schema do |s|
              s.object_type "Nested" do |t|
                t.field "user_id", "ID"
              end

              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.index "widgets" do |i|
                  i.route_with "nested.user_id"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("Field `Widget.nested.user_id` cannot be resolved, but it is referenced as an index `route_with` field."))
        end

        it "does not include a confusing 'must come after' message..." do
          expect {
            dump_schema do |s|
              s.object_type "Nested" do |t|
                t.field "user_id", "ID"
              end

              s.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "nested", "Nested"
                t.index "widgets" do |i|
                  i.route_with "nested.some_id"
                end
              end
            end
          }.to raise_error(Errors::SchemaError, a_string_including("Field `Widget.nested.some_id` cannot be resolved, but it is referenced as an index `route_with` field").and(excluding("must come before")))
        end
      end

      it "correctly overwrites built-in type customizations" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "month", "Int" do |f|
              f.mapping type: "byte"
              f.json_schema minimum: 0, maximum: 99
            end

            t.field "year", "Int" do |f|
              f.mapping type: "short"
              f.json_schema minimum: 2000, maximum: 2099
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "month" => {
              "anyOf" => [
                {
                  "allOf" => [
                    json_schema_integer,
                    {"minimum" => 0, "maximum" => 99}
                  ]
                },
                json_schema_null
              ]
            },
            "year" => {
              "anyOf" => [
                {
                  "allOf" => [
                    json_schema_integer,
                    {"minimum" => 2000, "maximum" => 2099}
                  ]
                },
                json_schema_null
              ]
            }
          },
          "required" => %w[month year]
        })
      end

      it "allows JSON schema options to be built up over multiple `json_schema` calls" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "month", "Int" do |f|
              f.json_schema minimum: 0
              f.json_schema maximum: 99
              f.json_schema minimum: 20 # demonstrate that the last call wins
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "month" => {
              "anyOf" => [
                {
                  "allOf" => [
                    json_schema_integer,
                    {"minimum" => 20, "maximum" => 99}
                  ]
                },
                json_schema_null
              ]
            }
          },
          "required" => %w[month]
        })
      end

      it "correctly restricts enum types with customizations" do
        json_schema = dump_schema do |s|
          s.enum_type "Color" do |t|
            t.values "RED", "ORANGE", "YELLOW", "GREEN", "BLUE", "INDIGO", "VIOLET"
          end

          s.object_type "MyType" do |t|
            t.field "primaryColor", "Color!" do |f|
              f.json_schema enum: %w[RED YELLOW BLUE]
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "primaryColor" => {
              "allOf" => [
                {"$ref" => "#/$defs/Color"},
                {"enum" => %w[RED YELLOW BLUE]}
              ]
            }
          },
          "required" => %w[primaryColor]
        })
      end

      it "applies customizations defined on a list field to the JSON schema array instead of applying them to the items" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "tags", "[String!]!" do |f|
              f.json_schema uniqueItems: true, maxItems: 1000
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "tags" => {
              "type" => "array",
              "items" => json_schema_string,
              "uniqueItems" => true,
              "maxItems" => 1000
            }
          },
          "required" => %w[tags]
        })
      end

      it "still applies customizations from the mapping type to array items" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "values", "[Int!]!" do |f|
              f.json_schema minItems: 1
              f.mapping type: "short"
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "values" => {
              "type" => "array",
              "items" => {
                "allOf" => [
                  json_schema_integer,
                  {"minimum" => -32768, "maximum" => 32767}
                ]
              },
              "minItems" => 1
            }
          },
          "required" => %w[values]
        })
      end

      it "raises a Errors::SchemaError when a conflicting type is specified" do
        dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "built_in_scalar_replaced", "String!" do |f|
              expect {
                f.json_schema type: "boolean"
              }.to raise_error(Errors::SchemaError, a_string_including(
                "Cannot override JSON schema type of field `built_in_scalar_replaced` with `boolean`"
              ))
            end
          end
        end
      end

      it "respects `json_schema` replacements set on a field definition, except when conflicting" do
        json_schema = dump_schema do |s|
          s.scalar_type "MyText" do |t|
            t.json_schema type: "string"
            t.mapping type: "keyword"
          end

          s.object_type "MyType" do |t|
            t.field "built_in_scalar_augmented", "String!" do |f|
              f.json_schema minLength: 4
            end
            t.field "custom_scalar", "MyText!"
            t.field "custom_scalar_augmented", "MyText!" do |f|
              f.json_schema minLength: 4
            end
          end
        end

        expect(json_schema).to have_json_schema_like("MyType", {
          "type" => "object",
          "properties" => {
            "built_in_scalar_augmented" => {
              "allOf" => [
                {"$ref" => "#/$defs/String"},
                {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH, "minLength" => 4}
              ]
            },
            "custom_scalar" => json_schema_ref("MyText!", is_keyword_type: true),
            "custom_scalar_augmented" => {
              "allOf" => [
                {"$ref" => "#/$defs/MyText"},
                {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH, "minLength" => 4}
              ]
            }
          },
          "required" => %w[built_in_scalar_augmented custom_scalar custom_scalar_augmented]
        })
      end

      it "respects `json_schema` customizations set on an object type definition" do
        define_point = lambda do |s|
          s.object_type "Point" do |t|
            t.field "x", "Float"
            t.field "y", "Float"
            t.json_schema type: "array", items: [{type: "number"}, {type: "number"}]
          end
        end

        define_my_type = lambda do |s|
          s.object_type "MyType" do |t|
            t.field "location", "Point"
          end
        end

        # We should get the same json schema regardless of which type is defined first.
        type_before_reference_json_schema = dump_schema do |s|
          define_point.call(s)
          define_my_type.call(s)
        end

        type_after_reference_json_schema = dump_schema do |s|
          define_my_type.call(s)
          define_point.call(s)
        end

        expect(type_before_reference_json_schema).to eq(type_after_reference_json_schema)
          .and have_json_schema_like("Point", {
            "type" => "array",
            "items" => [
              {"type" => "number"},
              {"type" => "number"}
            ]
          }).which_matches(
            [0, 0],
            [1, 2],
            [1234567890, 1234567890]
          ).and_fails_to_match(
            [nil, nil],
            %w[a b],
            nil
          )
      end

      describe "indexing-only fields" do
        it "allows the indexing-only fields to specify their customized json schema" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "date", "String", indexing_only: true do |f|
                f.mapping type: "date"
                f.json_schema format: "date-time"
              end
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "date" => {
                "anyOf" => [
                  {
                    "allOf" => [
                      {"$ref": "#/$defs/String"},
                      {"format" => "date-time"}
                    ]
                  },
                  json_schema_null
                ]
              }
            },
            "required" => %w[date]
          })
        end

        it "allows the indexing-only fields to be objects with nested fields" do
          json_schema = dump_schema do |s|
            s.object_type "NestedType" do |t|
              t.field "name", "String!"
            end

            s.object_type "MyType" do |t|
              t.field "nested", "NestedType!", indexing_only: true
            end
          end

          expect(json_schema).to have_json_schema_like("NestedType", {
            "type" => "object",
            "properties" => {
              "name" => json_schema_ref("String!")
            },
            "required" => ["name"]
          })

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "nested" => json_schema_ref("NestedType!")
            },
            "required" => %w[nested]
          })
        end

        it "raises an error when same mapping field is defined twice with different JSON schemas" do
          expect {
            dump_schema do |s|
              s.object_type "Card" do |t|
                t.field "meta", "Int" do |f|
                  f.mapping type: "integer"
                  f.json_schema minimum: 10
                end

                t.field "meta", "Int", indexing_only: true do |f|
                  f.mapping type: "integer"
                  f.json_schema minimum: 20
                end
              end
            end
          }.to raise_error Errors::SchemaError, a_string_including("Duplicate indexing field", "Card", "meta", "graphql_only: true")
        end
      end

      it "generates the JSON schema of an array for a `paginated_collection_field`" do
        json_schema = dump_schema do |s|
          s.object_type "Widget" do |t|
            t.paginated_collection_field "names", "String"
          end
        end

        expect(json_schema).to have_json_schema_like("Widget", {
          "type" => "object",
          "properties" => {
            "names" => {
              "type" => "array",
              "items" => json_schema_string
            }
          },
          "required" => %w[names]
        })
      end

      it "honors JSON schema customizations of a `paginated_collection_field`" do
        json_schema = dump_schema do |s|
          s.object_type "Widget" do |t|
            t.paginated_collection_field "names", "String" do |f|
              f.json_schema uniqueItems: true, maxItems: 1000
            end
          end
        end

        expect(json_schema).to have_json_schema_like("Widget", {
          "type" => "object",
          "properties" => {
            "names" => {
              "type" => "array",
              "items" => json_schema_string,
              "uniqueItems" => true,
              "maxItems" => 1000
            }
          },
          "required" => %w[names]
        })
      end

      describe "relation fields" do
        context "on a relation with an outbound foreign key" do
          it "includes a non-null foreign key field if the GraphQL relation field is non-null" do
            json_schema = dump_schema do |s|
              s.object_type "OtherType" do |t|
                t.field "id", "ID!"
              end

              s.object_type "MyType" do |t|
                t.relates_to_one "other", "OtherType!", via: "other_id", dir: :out
              end
            end

            expect(json_schema).to have_json_schema_like("MyType", {
              "type" => "object",
              "properties" => {
                "other_id" => json_schema_ref("ID!")
              },
              "required" => %w[other_id]
            })
          end

          it "includes a nullable foreign key field if the GraphQL relation field is nullable" do
            json_schema = dump_schema do |s|
              s.object_type "OtherType" do |t|
                t.field "id", "ID!"
              end

              s.object_type "MyType" do |t|
                t.relates_to_one "other", "OtherType", via: "other_id", dir: :out
              end
            end

            expect(json_schema).to have_json_schema_like("MyType", {
              "type" => "object",
              "properties" => {
                "other_id" => json_schema_ref("ID")
              },
              "required" => %w[other_id]
            })
          end

          it "includes an array foreign key field if its a `relates_to_many` field" do
            json_schema = dump_schema do |s|
              s.object_type "OtherType" do |t|
                t.field "id", "ID!"
                t.index "other_type"
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.relates_to_many "others", "OtherType", via: "other_ids", dir: :out, singular: "other"
                t.index "my_type"
              end
            end

            expect(json_schema).to have_json_schema_like("MyType", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                "other_ids" => {
                  "type" => "array",
                  "items" => json_schema_id
                }
              },
              "required" => %w[id other_ids]
            })
          end

          it "includes a non-null `id` field if the relation is self-referential, even if there is no `id` GraphQL field (for a `relates_to_one` case)" do
            json_schema = dump_schema do |s|
              s.object_type "MyType" do |t|
                t.relates_to_one "parent", "MyType!", via: "parent_id", dir: :out
              end
            end

            expect(json_schema).to have_json_schema_like("MyType", {
              "type" => "object",
              "properties" => {
                "parent_id" => json_schema_ref("ID!"),
                "id" => json_schema_ref("ID!")
              },
              "required" => %w[parent_id id]
            })
          end
        end

        context "on a relation with an inbound foreign key" do
          it "includes the foreign key field when the relation is self-referential, regardless of the details of the relation (nullable or not, one or many)" do
            json_schema = dump_schema do |s|
              s.object_type "MyTypeOneNullable" do |t|
                t.field "id", "ID!"
                t.relates_to_one "parent", "MyTypeOneNullable", via: "children_ids", dir: :in
                t.index "my_type1"
              end

              s.object_type "MyTypeOneNonNull" do |t|
                t.field "id", "ID!"
                t.relates_to_one "parent", "MyTypeOneNonNull!", via: "children_ids", dir: :in
                t.index "my_type2"
              end

              s.object_type "MyTypeBothDirections" do |t|
                t.field "id", "ID!"
                t.relates_to_one "parent", "MyTypeBothDirections!", via: "children_ids", dir: :in
                t.relates_to_many "children", "MyTypeBothDirections", via: "children_ids", dir: :out, singular: "child"
                t.index "my_type2"
              end

              s.object_type "MyTypeMany" do |t|
                t.field "id", "ID!"
                t.relates_to_many "children", "MyTypeMany", via: "parent_id", dir: :in, singular: "child"
                t.index "my_type3"
              end
            end

            expect(json_schema).to have_json_schema_like("MyTypeOneNullable", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                # technically this would probably be an array field, but there's not enough info on this side of the relation to know.
                # When the other side is also defined (as in `both_dirs`) it is more accurate.
                "children_ids" => json_schema_ref("ID")
              },
              "required" => %w[id children_ids]
            })

            expect(json_schema).to have_json_schema_like("MyTypeOneNonNull", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                # technically this would probably be an array field, but there's not enough info on this side of the relation to know.
                # When the other side is also defined (see another test) it is more accurate.
                "children_ids" => json_schema_ref("ID!")
              },
              "required" => %w[id children_ids]
            })

            expect(json_schema).to have_json_schema_like("MyTypeBothDirections", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                "children_ids" => {
                  "type" => "array",
                  "items" => json_schema_id
                }
              },
              "required" => %w[id children_ids]
            })

            expect(json_schema).to have_json_schema_like("MyTypeMany", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                "parent_id" => json_schema_ref("ID")
              },
              "required" => %w[id parent_id]
            })
          end
        end

        it "prefers defined fields to fields inferred by relations when the same field is created by both, as defined fields are more accurate" do
          json_schema = dump_schema do |s|
            s.object_type "CardInferred" do |t|
              t.relates_to_one "cloned_from_card", "CardInferred", via: "cloned_from_card_id", dir: :out
            end

            s.object_type "CardExplicit" do |t|
              t.relates_to_one "cloned_from_card", "CardInferred", via: "cloned_from_card_id", dir: :out
              t.field "cloned_from_card_id", "ID!"
            end
          end

          expect(json_schema).to have_json_schema_like("CardInferred", {
            "type" => "object",
            "properties" => {
              "cloned_from_card_id" => json_schema_ref("ID"),
              "id" => json_schema_ref("ID!")
            },
            "required" => %w[cloned_from_card_id id]
          })

          expect(json_schema).to have_json_schema_like("CardExplicit", {
            "type" => "object",
            "properties" => {
              "cloned_from_card_id" => json_schema_ref("ID!")
            },
            "required" => %w[cloned_from_card_id]
          })
        end
      end

      context "`nullable:` option inside `json_schema`" do
        it "forces field that is nullable in GraphQL to be non-nullable in the generated JSON schema" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "size", "Float" do |f|
                f.json_schema nullable: false
              end
              t.field "cost", "Float"
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "size" => json_schema_ref("Float!"),
              "cost" => json_schema_ref("Float")
            },
            "required" => %w[size cost]
          })
        end

        it "has no effect on an already-non-nullable field" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "id", "ID!"
              t.field "size", "Float!" do |f|
                f.json_schema nullable: false
              end
              t.field "cost", "Float!"
              t.index "my_type"
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "id" => json_schema_ref("ID!"),
              "size" => json_schema_ref("Float!"),
              "cost" => json_schema_ref("Float!")
            },
            "required" => %w[id size cost]
          })
        end

        it "forces wrapped field that is nullable in GraphQL to be non-nullable in the generated JSON schema" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "size", "[[Float!]]" do |f|
                f.json_schema nullable: false
              end
              t.field "cost", "[[Float!]]"
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "size" => {
                "type" => "array",
                "items" => {
                  "anyOf" => [
                    {
                      "type" => "array",
                      "items" => json_schema_float
                    },
                    json_schema_null
                  ]
                }
              },
              "cost" => {
                "anyOf" => [
                  {
                    "type" => "array",
                    "items" => {
                      "anyOf" => [
                        {
                          "type" => "array",
                          "items" => json_schema_float
                        },
                        json_schema_null
                      ]
                    }
                  },
                  json_schema_null
                ]
              }
            },
            "required" => %w[size cost]
          })
        end

        it "has no effect on an already-non-nullable wrapped field" do
          json_schema = dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "size", "[[Float!]]!" do |f|
                f.json_schema nullable: false
              end
              t.field "cost", "[[Float!]]!"
            end
          end

          expect(json_schema).to have_json_schema_like("MyType", {
            "type" => "object",
            "properties" => {
              "size" => {
                "type" => "array",
                "items" => {
                  "anyOf" => [
                    {
                      "type" => "array",
                      "items" => json_schema_float
                    },
                    json_schema_null
                  ]
                }
              },
              "cost" => {
                "type" => "array",
                "items" => {
                  "anyOf" => [
                    {
                      "type" => "array",
                      "items" => json_schema_float
                    },
                    json_schema_null
                  ]
                }
              }
            },
            "required" => %w[size cost]
          })
        end

        it "raises an exception on `nullable: true` because we cannot allow that for non-null GraphQL fields and `nullable: true` does nothing on an already nullable GraphQL field`" do
          dump_schema do |s|
            s.object_type "MyType" do |t|
              t.field "size", "[[Float!]]" do |f|
                expect {
                  f.json_schema nullable: true
                }.to raise_error(Errors::SchemaError, a_string_including("`nullable: true` is not allowed on a field--just declare the GraphQL field as being nullable (no `!` suffix) instead."))
              end
            end
          end
        end

        it "is not allowed on an object or scalar type (it is only intended for use on fields)" do
          dump_schema do |s|
            s.object_type "MyType" do |t|
              expect {
                t.json_schema nullable: false
              }.to raise_error(Errors::SchemaError, a_string_including("Invalid JSON schema options", "nullable"))
            end

            s.scalar_type "ScalarType" do |t|
              t.mapping type: "boolean"
              t.json_schema type: "boolean"

              expect {
                t.json_schema nullable: false
              }.to raise_error(Errors::SchemaError, a_string_including("Invalid JSON schema options", "nullable"))
            end
          end
        end
      end

      it "dumps object schemas with a __typename property" do
        json_schema = dump_schema do |s|
          s.object_type "MyType" do |t|
            t.field "id", "ID!"
          end
        end

        expect(json_schema.dig("$defs", "MyType", "properties", "__typename")).to eq({
          "const" => "MyType",
          "default" => "MyType",
          "type" => "string"
        })
      end

      shared_examples_for "a type with subtypes" do |type_def_method|
        context "composed of 2 indexed types" do
          it "generates separate json schemas for the two subtypes and the supertype" do
            schemas = dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "amount_cents", "Int!"
                link_subtype_to_supertype(t, "Thing")
                t.index "widgets"
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "weight", "Int!"
                link_subtype_to_supertype(t, "Thing")
                t.index "components"
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
              end
            end

            expect(schemas).to have_json_schema_like("Widget", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                "name" => json_schema_ref("String!"),
                "amount_cents" => json_schema_ref("Int!")
              },
              "required" => %w[id name amount_cents]
            })

            expect(schemas).to have_json_schema_like("Component", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                "name" => json_schema_ref("String!"),
                "weight" => json_schema_ref("Int!")
              },
              "required" => %w[id name weight]
            })

            expect(schemas).to have_json_schema_like("Thing", {
              "required" => [
                "__typename"
              ],
              "oneOf" => [
                {
                  "$ref" => "#/$defs/Widget"
                },
                {
                  "$ref" => "#/$defs/Component"
                }
              ]
            })

            type_definitions = schemas.fetch("$defs")
            expect(type_definitions.keys).to include("Thing")
            expect(envelope_type_enum_values(type_definitions)).to contain_exactly("Widget", "Component")
          end
        end

        context "that is itself indexed" do
          it "uses `oneOf` to produce a JSON schema that exclusively validates one or the other type" do
            json_schema = dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "amount_cents", "Int!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "id", "ID!"
                t.field "name", "String!"
                t.field "weight", "Int!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
                t.index "things"
              end
            end

            expect(json_schema).to have_json_schema_like("Thing", {
              "required" => ["__typename"],
              "oneOf" => [
                {"$ref" => "#/$defs/Widget"},
                {"$ref" => "#/$defs/Component"}
              ]
            }).which_matches(
              {"id" => "1", "name" => "foo", "amount_cents" => 12, "__typename" => "Widget"},
              {"id" => "1", "name" => "foo", "weight" => 12, "__typename" => "Component"}
            ).and_fails_to_match(
              {"id" => "1", "name" => "foo", "__typename" => "Widget"},
              nil
            )
          end
        end

        context "that is an embedded type" do
          it "uses `oneOf` to produce a JSON schema that exclusively validates one or the other type" do
            json_schema = dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "name", "String!"
                t.field "amount_cents", "Int!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "name", "String!"
                t.field "weight", "Int!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
              end

              s.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "thing", "Thing!"
                t.index "my_type"
              end
            end

            expect(json_schema).to have_json_schema_like("Thing", {
              "required" => ["__typename"],
              "oneOf" => [
                {"$ref" => "#/$defs/Widget"},
                {"$ref" => "#/$defs/Component"}
              ]
            })

            expect(json_schema).to have_json_schema_like("MyType", {
              "type" => "object",
              "properties" => {
                "id" => json_schema_ref("ID!"),
                "thing" => json_schema_ref("Thing!"),
                "__typename" => {
                  "type" => "string",
                  "const" => "MyType",
                  "default" => "MyType"
                }
              },
              "required" => %w[id thing]
            }).which_matches(
              {"id" => "a", "thing" => {"id" => "a", "name" => "foo", "amount_cents" => 12, "__typename" => "Widget"}},
              {"id" => "a", "thing" => {"id" => "a", "name" => "foo", "weight" => 12, "__typename" => "Component"}}
            ).and_fails_to_match(
              {"id" => "a", "name" => "foo", "__typename" => "Widget"},
              {"id" => "a", "thing" => nil},
              nil
            )
          end

          it "generates a JSON schema that correctly allows null values when the supertype field is nullable" do
            json_schema = dump_schema do |s|
              s.object_type "Widget" do |t|
                t.field "name", "String!"
                t.field "amount_cents", "Int!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.object_type "Component" do |t|
                t.field "name", "String!"
                t.field "weight", "Int!"
                link_subtype_to_supertype(t, "Thing")
              end

              s.public_send type_def_method, "Thing" do |t|
                link_supertype_to_subtypes(t, "Widget", "Component")
              end

              s.object_type "MyType" do |t|
                t.field "thing", "Thing"
              end
            end

            expect(json_schema).to have_json_schema_like("MyType", {
              "type" => "object",
              "properties" => {
                "thing" => json_schema_ref("Thing"),
                "__typename" => {
                  "type" => "string",
                  "const" => "MyType",
                  "default" => "MyType"
                }
              },
              "required" => %w[thing]
            }).which_matches(
              {"thing" => {"id" => "a", "name" => "foo", "amount_cents" => 12, "__typename" => "Widget"}},
              {"thing" => {"id" => "a", "name" => "foo", "weight" => 12, "__typename" => "Component"}},
              {"thing" => nil}
            ).and_fails_to_match(
              {"name" => "foo", "__typename" => "Widget"},
              nil
            )
          end

          it "allows the same field on two subtypes to have different json_schema" do
            json_schema = dump_schema do |s|
              s.object_type "Person" do |t|
                t.field "name", "String" do |f|
                  f.json_schema nullable: false
                end
                t.field "nationality", "String!"
                link_subtype_to_supertype(t, "Inventor")
              end

              s.object_type "Company" do |t|
                t.field "name", "String" do |f|
                  f.json_schema maxLength: 20
                end
                t.field "stock_ticker", "String!"
                link_subtype_to_supertype(t, "Inventor")
              end

              s.public_send type_def_method, "Inventor" do |t|
                link_supertype_to_subtypes(t, "Person", "Company")
              end
            end

            expect(json_schema).to have_json_schema_like("Person", {
              "type" => "object",
              "properties" => {
                "name" => json_schema_ref("String!"),
                "nationality" => json_schema_ref("String!")
              },
              "required" => %w[name nationality]
            })

            expect(json_schema).to have_json_schema_like("Company", {
              "type" => "object",
              "properties" => {
                "name" => {
                  "anyOf" => [
                    {
                      "allOf" => [
                        {"$ref" => "#/$defs/String"},
                        {"maxLength" => 20}
                      ]
                    },
                    {"type" => "null"}
                  ]
                },
                "stock_ticker" => json_schema_ref("String!")
              },
              "required" => %w[name stock_ticker]
            })
          end
        end
      end

      context "on a type union" do
        include_examples "a type with subtypes", :union_type do
          def link_subtype_to_supertype(object_type, supertype_name)
            # nothing to do; the linkage happens via a `subtypes` call on the supertype
          end

          def link_supertype_to_subtypes(union_type, *subtype_names)
            union_type.subtypes(*subtype_names)
          end
        end
      end

      context "on an interface type" do
        include_examples "a type with subtypes", :interface_type do
          def link_subtype_to_supertype(object_type, interface_name)
            object_type.implements interface_name
          end

          def link_supertype_to_subtypes(interface_type, *subtype_names)
            # nothing to do; the linkage happens via an `implements` call on the subtype
          end
        end

        it "supports interface recursion (e.g. an interface that implements an interface)" do
          json_schema = dump_schema do |s|
            s.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "name", "String!"
              t.field "amount_cents", "Int!"
              t.implements "WidgetOrComponent"
            end

            s.object_type "Component" do |t|
              t.field "id", "ID!"
              t.field "name", "String!"
              t.field "weight", "Int!"
              t.implements "WidgetOrComponent"
            end

            s.interface_type "WidgetOrComponent" do |t|
              t.implements "Thing"
            end

            s.object_type "Object" do |t|
              t.field "id", "ID!"
              t.field "description", "String!"
              t.implements "Thing"
            end

            s.interface_type "Thing" do |t|
              t.field "id", "ID!"
              t.index "things"
            end
          end

          expect(json_schema).to have_json_schema_like("Thing", {
            "required" => ["__typename"],
            "oneOf" => [
              {"$ref" => "#/$defs/Widget"},
              {"$ref" => "#/$defs/Component"},
              {"$ref" => "#/$defs/Object"}
            ]
          }).which_matches(
            {"id" => "1", "name" => "foo", "amount_cents" => 12, "__typename" => "Widget"},
            {"id" => "1", "name" => "foo", "weight" => 12, "__typename" => "Component"},
            {"id" => "1", "description" => "foo", "__typename" => "Object"}
          ).and_fails_to_match(
            {"id" => "1", "name" => "foo", "__typename" => "Widget"},
            nil
          )
        end
      end

      it "dumps the types by name in alphabetical order (minus the envelope type at the start) for consistent dump output" do
        schemas1 = all_type_definitions_for do |s|
          s.object_type "AType" do |t|
            t.field "id", "ID!"
            t.index "a_type"
          end

          s.object_type "BType" do |t|
            t.field "id", "ID!"
            t.index "b_type"
          end
        end

        schemas2 = all_type_definitions_for do |s|
          s.object_type "BType" do |t|
            t.field "id", "ID!"
            t.index "b_type"
          end

          s.object_type "AType" do |t|
            t.field "id", "ID!"
            t.index "a_type"
          end
        end

        # The types should have alphabetical keys (except the envelope always goes first; hence the `drop(1)`)
        expect(schemas1.keys.drop(1)).to eq schemas1.keys.drop(1).sort
        expect(schemas2.keys.drop(1)).to eq schemas2.keys.drop(1).sort

        # ...and the types should be alphabetically listed within the envelope, too.
        expect(envelope_type_enum_values(schemas1)).to eq %w[AType BType]
        expect(envelope_type_enum_values(schemas2)).to eq %w[AType BType]
      end

      it "does not dump a schema for a derived indexed type because it cannot be directly ingested by the indexer" do
        schemas = all_type_definitions_for do |s|
          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "workspace_id", "ID"
            t.index "widgets"
            t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
              derive.append_only_set "widget_ids", from: "id"
            end
          end

          s.object_type "WidgetWorkspace" do |t|
            t.field "id", "ID!"
            t.field "widget_ids", "[ID!]!"
            t.index "widget_workspaces"
          end
        end

        expect(schemas.keys).to include(EVENT_ENVELOPE_JSON_SCHEMA_NAME, "Widget")
        expect(schemas.keys).to exclude("WidgetWorkspace")
        expect(envelope_type_enum_values(schemas)).to eq ["Widget"]
      end

      it "raises a clear error if the schema defines a type with a reserved name" do
        dump_schema do |s|
          expect {
            s.object_type EVENT_ENVELOPE_JSON_SCHEMA_NAME
          }.to raise_error Errors::SchemaError, a_string_including(EVENT_ENVELOPE_JSON_SCHEMA_NAME, "reserved name")
        end
      end

      it "sets json_schema_version to the specified (valid) value" do
        result = define_schema(schema_element_name_form: "snake_case") do |s|
          s.json_schema_version 1
        end.json_schemas_for(1)

        expect(result[JSON_SCHEMA_VERSION_KEY]).to eq(1)
      end

      it "fails if json_schema_version is set to invalid values" do
        expect {
          define_schema(schema_element_name_form: "snake_case") do |s|
            s.json_schema_version 0.5
          end
        }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer. Specified version: 0.5"))

        expect {
          define_schema(schema_element_name_form: "snake_case") do |s|
            s.json_schema_version "asd"
          end
        }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer. Specified version: asd"))

        expect {
          define_schema(schema_element_name_form: "snake_case") do |s|
            s.json_schema_version 0
          end
        }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer. Specified version: 0"))

        expect {
          define_schema(schema_element_name_form: "snake_case") do |s|
            s.json_schema_version(-1)
          end
        }.to raise_error(Errors::SchemaError, a_string_including("must be a positive integer. Specified version: -1"))
      end

      it "fails if json_schema_version is left unset" do
        expect {
          define_schema(schema_element_name_form: "snake_case", json_schema_version: nil) {}.available_json_schema_versions
        }.to raise_error(Errors::SchemaError, a_string_including("must be specified in the schema"))
      end

      it "fails if json_schema_version is set multiple times" do
        expect {
          define_schema(schema_element_name_form: "snake_case") do |s|
            s.json_schema_version 1
            s.json_schema_version 2
          end
        }.to raise_error(Errors::SchemaError, a_string_including("can only be set once", "Previously-set version: 1"))
      end

      it "is unable to return a non-existent schema version" do
        expect {
          define_schema(schema_element_name_form: "snake_case") do |s|
            s.json_schema_version 1
          end.json_schemas_for(2)
        }.to raise_error(Errors::NotFoundError, a_string_including("The requested json schema version (2) is not available", "Available versions: 1"))
      end

      it "ignores runtime fields during json schema generation" do
        json_schema = dump_schema do |schema|
          schema.object_type "Widget" do |t|
            t.field "test_runtime_field", "String" do |f|
              f.runtime_script "example test script"
            end
          end
        end

        widget_def = json_schema.fetch("$defs").fetch("Widget")
        expect(widget_def["properties"].keys).not_to include("test_runtime_field")
      end

      def all_type_definitions_for(&schema_definition)
        dump_schema(&schema_definition).fetch("$defs")
      end

      def dump_schema(type_name_overrides: {}, enum_value_overrides_by_type: {}, &schema_definition)
        define_schema(
          schema_element_name_form: "snake_case",
          type_name_overrides: type_name_overrides,
          enum_value_overrides_by_type: enum_value_overrides_by_type,
          &schema_definition
        ).current_public_json_schema
      end

      def envelope_type_enum_values(schemas)
        schemas.dig(EVENT_ENVELOPE_JSON_SCHEMA_NAME, "properties", "type", "enum")
      end

      def json_schema_ref(type, is_keyword_type: %w[ID! ID String! String].include?(type))
        if type.end_with?("!")
          basic_json_schema_ref = {"$ref" => "#/$defs/#{type.delete_suffix("!")}"}

          if is_keyword_type
            {
              "allOf" => [
                basic_json_schema_ref,
                {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
              ]
            }
          else
            basic_json_schema_ref
          end
        else
          {
            "anyOf" => [
              json_schema_ref("#{type}!", is_keyword_type: is_keyword_type),
              {"type" => "null"}
            ]
          }
        end
      end

      def shard_routing_string_field
        {
          "allOf" => [
            {"$ref" => "#/$defs/ID"},
            {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH, "pattern" => Indexing::Index::HAS_NON_WHITE_SPACE_REGEX}
          ]
        }
      end
    end
  end
end
