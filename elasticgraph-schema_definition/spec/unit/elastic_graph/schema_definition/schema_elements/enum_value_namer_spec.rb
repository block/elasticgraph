# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/schema_elements/enum_value_namer"
require "graphql"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      RSpec.describe EnumValueNamer do
        describe "#name_for" do
          it "echoes back the given value name if no override has been provided for the type" do
            namer = EnumValueNamer.new

            expect(namer.name_for("DayOfWeek", "MONDAY")).to eq("MONDAY")
          end

          it "echoes back the given value name if the named type has overrides but not for the given value" do
            namer = EnumValueNamer.new({"DayOfWeek" => {"TUESDAY" => "TUE"}})

            expect(namer.name_for("DayOfWeek", "MONDAY")).to eq("MONDAY")
          end

          it "returns the override value for the given type and value if one has been provided" do
            namer = EnumValueNamer.new({"DayOfWeek" => {"TUESDAY" => "TUE"}})

            expect(namer.name_for("DayOfWeek", "TUESDAY")).to eq("TUE")
          end

          it "allows the overrides to be configured with string or symbol keys" do
            namer1 = EnumValueNamer.new({"DayOfWeek" => {"TUESDAY" => "TUE"}})
            namer2 = EnumValueNamer.new({DayOfWeek: {TUESDAY: "TUE"}})

            expect(namer1).to eq(namer2)
          end

          it "does not allow an override to produce an invalid GraphQL name" do
            expect {
              EnumValueNamer.new({DayOfWeek: {TUESDAY: "The day after Monday"}})
            }.to raise_error Errors::ConfigError, a_string_including(
              "Provided `enum_value_overrides_by_type_name` have 1 problem(s)",
              "`The day after Monday` (the override for `DayOfWeek.TUESDAY`) is not a valid GraphQL type name. #{GRAPHQL_NAME_VALIDITY_DESCRIPTION}"
            )
          end

          it "does not allow two overrides on the same type to map to the same name" do
            expect {
              EnumValueNamer.new({DayOfWeek: {MONDAY: "MON", TUESDAY: "MON"}})
            }.to raise_error Errors::ConfigError, a_string_including(
              "Provided `enum_value_overrides_by_type_name` have 1 problem(s)",
              "Multiple `DayOfWeek` enum value overrides (MONDAY, TUESDAY) map to the same name (MON)"
            )
          end

          it "keeps track of which overrides have and have not been used" do
            namer = EnumValueNamer.new(
              DayOfWeek: {MONDAY: "MON", TUESDAY: "TUE"},
              MetricUnit: {GRAM: "G"},
              Other: {}
            )

            expect(namer.unused_overrides).to eq({
              "DayOfWeek" => {"MONDAY" => "MON", "TUESDAY" => "TUE"},
              "MetricUnit" => {"GRAM" => "G"},
              "Other" => {}
            })
            expect(namer.used_value_names_by_type_name).to be_empty

            namer.name_for("DayOfWeek", "TUESDAY")
            namer.name_for("MetricUnit", "GRAM")
            namer.name_for("MetricUnit", "METER")
            namer.name_for("SomeEnum", "FOO")

            expect(namer.unused_overrides).to eq({
              "DayOfWeek" => {"MONDAY" => "MON"},
              "Other" => {}
            })
            expect(namer.used_value_names_by_type_name).to eq({
              "DayOfWeek" => %w[TUESDAY],
              "MetricUnit" => %w[GRAM METER],
              "SomeEnum" => %w[FOO]
            })
          end

          it "does not allow `used_value_names_by_type_name` to be mutated when a caller queries it" do
            namer = EnumValueNamer.new

            expect(namer.used_value_names_by_type_name["Foo"]).to be_empty
            expect(namer.used_value_names_by_type_name).to be_empty
          end
        end
      end
    end
  end
end
