# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/schema_elements/type_namer"
require "graphql"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      RSpec.describe TypeNamer do
        describe "#name_for" do
          it "echoes back the given string or symbol as a string if no override has been provided" do
            namer = TypeNamer.new

            expect(namer.name_for("SomeName")).to eq "SomeName"
            expect(namer.name_for(:SomeName)).to eq "SomeName"
          end

          it "returns the configured override if there is one" do
            namer = TypeNamer.new(name_overrides: {SomeName: "SomeNameAlt"})

            expect(namer.name_for(:SomeName)).to eq "SomeNameAlt"
            expect(namer.name_for("SomeName")).to eq "SomeNameAlt"
          end

          it "allows the overrides to be configured with string or symbol keys" do
            namer1 = TypeNamer.new(name_overrides: {SomeName: "SomeNameAlt"})
            namer2 = TypeNamer.new(name_overrides: {"SomeName" => "SomeNameAlt"})

            expect(namer1).to eq(namer2)
          end

          it "does not allow an override to produce an invalid GraphQL name" do
            expect {
              TypeNamer.new(name_overrides: {SomeName: "Not a valid name"})
            }.to raise_error Errors::ConfigError, a_string_including(
              "Provided type name overrides have 1 problem(s)",
              "`Not a valid name` (the override for `SomeName`) is not a valid GraphQL type name. #{GRAPHQL_NAME_VALIDITY_DESCRIPTION}"
            )
          end

          it "keeps track of which overrides have and have not been used" do
            namer = TypeNamer.new(name_overrides: {SomeName: "SomeNameAlt", OtherName: "Foo", FinalName: "Bar"})

            expect(namer.unused_name_overrides).to eq({"SomeName" => "SomeNameAlt", "OtherName" => "Foo", "FinalName" => "Bar"})
            expect(namer.used_names).to be_empty

            namer.name_for("SomeName")

            expect(namer.unused_name_overrides).to eq({"OtherName" => "Foo", "FinalName" => "Bar"})
            expect(namer.used_names).to contain_exactly("SomeName")

            namer.name_for("FinalName")
            namer.name_for("SomeName")
            namer.name_for("NameThatHasNoOveride")

            expect(namer.unused_name_overrides).to eq({"OtherName" => "Foo"})
            expect(namer.used_names).to contain_exactly("SomeName", "FinalName", "NameThatHasNoOveride")
          end
        end

        TypeNamer::TYPES_THAT_CANNOT_BE_OVERRIDDEN.each do |type|
          it "does not allow a user to override the `#{type}` since it is part of the GraphQL spec and cannot be changed" do
            expect {
              TypeNamer.new(name_overrides: {type.to_sym => "#{type}Alt"})
            }.to raise_error Errors::ConfigError, a_string_including(
              "Provided type name overrides have 1 problem(s)",
              "`#{type}` cannot be overridden because it is part of the GraphQL spec."
            )
          end
        end

        describe "#revert_override_for" do
          it "echoes back the given name if it has not and overridden name" do
            namer = TypeNamer.new

            expect(namer.revert_override_for("SomeName")).to eq "SomeName"
          end

          it "returns the original name if the given name has an override" do
            namer = TypeNamer.new(name_overrides: {SomeName: "SomeNameAlt"})

            expect(namer.revert_override_for("SomeNameAlt")).to eq "SomeName"
          end

          it "avoids ambiguities by disallowing multiple names overrides that map to the same result" do
            expect {
              TypeNamer.new(name_overrides: {SomeName: "SomeNameAlt", Other: "SomeNameAlt"})
            }.to raise_error Errors::ConfigError, a_string_including(
              "Provided type name overrides have 1 problem(s)",
              "1. Multiple names (Other, SomeName) map to the same override: SomeNameAlt, which is not supported."
            )
          end
        end

        describe "generated names" do
          tested_formats = ::Set.new

          after(:context) do
            untested_formats = TypeNamer::DEFAULT_FORMATS.keys - tested_formats.to_a

            expect(untested_formats).to be_empty, "Expected all `TypeNamer::DEFAULT_FORMATS.keys` to be tested via the " \
              "`a TypeNamer format` shared example group, but #{untested_formats.size} were not: #{untested_formats.to_a.inspect}."
          end

          shared_examples_for "a TypeNamer format" do |format_name:, valid_args:, valid_args_result:|
            tested_formats << format_name
            let(:default_format) { TypeNamer::DEFAULT_FORMATS.fetch(format_name) }

            it "has a default format" do
              namer = TypeNamer.new
              name = namer.generate_name_for(format_name, **valid_args)

              expect(name).to eq valid_args_result
              expect(namer.matches_format?(name, format_name)).to be true
              expect(namer.matches_format?(name + "_", format_name)).to be false
            end

            it "allows the default format to be overridden" do
              namer = TypeNamer.new(format_overrides: {format_name => "#{default_format}Alt"})
              name = namer.generate_name_for(format_name, **valid_args)

              expect(name).to eq "#{valid_args_result}Alt"
              expect(namer.matches_format?(name, format_name)).to be true
              expect(namer.matches_format?(name + "_", format_name)).to be false
            end

            it "does not apply a configured name override, requiring that of the caller, to avoid excessive application of that logic" do
              namer = TypeNamer.new(name_overrides: {valid_args_result => "SomethingCompletelyDifferent"})
              name = namer.generate_name_for(format_name, **valid_args)

              expect(name).to eq valid_args_result
            end

            it "raises a clear error when an overridden format would produce an invalid GraphQL name" do
              expect_instantiation_config_error(
                %(1. The #{format_name} format "3#{default_format}" does not produce a valid GraphQL type name. #{GRAPHQL_NAME_VALIDITY_DESCRIPTION}),
                format_name => "3#{default_format}"
              )
            end

            it "raises a clear error when its override omits a placeholder" do
              expect_instantiation_config_error(
                %(1. The #{format_name} format "#{format_name}Alt" is missing required placeholders: #{valid_args.keys.join(", ")}. Example valid format: "#{default_format}".),
                format_name => "#{format_name}Alt"
              )
            end

            it "raises a clear error when its includes an unknown placeholder" do
              expect_instantiation_config_error(
                %(1. The #{format_name} format "#{default_format}Alt%{extra1}%{extra2}" has excess placeholders: extra1, extra2. Example valid format: "#{default_format}".),
                format_name => "#{default_format}Alt%{extra1}%{extra2}"
              )
            end

            it "raises a clear error when asked to generate a name with a misspelled argument" do
              (first_key, first_value), *rest_args = valid_args.to_a
              args = {"#{first_key}2": first_value, **rest_args.to_h}

              expect_generate_name_error(format_name, "omits required key(s): #{first_key}", **args)
            end

            it "raises a clear error when asked to generate a name with a missing argument" do
              (first_key, _), *rest_args = valid_args.to_a

              expect_generate_name_error(format_name, "omits required key(s): #{first_key}", **rest_args.to_h)
            end

            it "raises a clear error when asked to generate a name with an extra argument" do
              args = {extra_arg: "Foo", **valid_args}

              expect_generate_name_error(format_name, "contains extra key(s): extra_arg", **args)
            end

            if TypeNamer::REQUIRED_PLACEHOLDERS.fetch(format_name) == [:base]
              it "extracts the base name from an example name in the default format" do
                namer = TypeNamer.new
                name = namer.generate_name_for(format_name, base: "SomeTypeName")

                expect(namer.extract_base_from(name, format: format_name)).to eq "SomeTypeName"
              end

              it "extracts the base name from an example name in an overridden format" do
                namer = TypeNamer.new(format_overrides: {format_name => "Pre#{default_format}Post"})
                name = namer.generate_name_for(format_name, base: "SomeTypeName")

                expect(namer.extract_base_from(name, format: format_name)).to eq "SomeTypeName"
              end

              it "returns `nil` if the provided name does not match the format" do
                namer = TypeNamer.new

                expect(namer.extract_base_from("", format: format_name)).to eq nil
                expect(namer.extract_base_from("Invalid", format: format_name)).to eq nil
              end
            else
              it "raises a clear error indicating this format does not support base extraction since it's format is not limited to a single `base` parameter" do
                namer = TypeNamer.new
                name = namer.generate_name_for(format_name, **valid_args)

                expect {
                  namer.extract_base_from(name, format: format_name)
                }.to raise_error Errors::InvalidArgumentValueError, "The `#{format_name}` format does not support base extraction."

                expect {
                  namer.extract_base_from("", format: format_name)
                }.to raise_error Errors::InvalidArgumentValueError, "The `#{format_name}` format does not support base extraction."
              end
            end
          end

          [
            :AggregatedValues,
            :GroupedBy,
            :Aggregation,
            :Connection,
            :Edge,
            :FilterInput,
            :ListFilterInput,
            :FieldsListFilterInput,
            :ListElementFilterInput,
            :SortOrder
          ].each do |simple_format_name|
            describe "the #{simple_format_name} format" do
              include_examples "a TypeNamer format", {
                format_name: simple_format_name,
                valid_args: {base: "Widget"},
                valid_args_result: "Widget#{simple_format_name}"
              }
            end
          end

          describe "the InputEnum format" do
            include_examples "a TypeNamer format", {
              format_name: :InputEnum,
              valid_args: {base: "Month"},
              valid_args_result: "MonthInput"
            }
          end

          describe "the SubAggregation format" do
            include_examples "a TypeNamer format", {
              format_name: :SubAggregation,
              valid_args: {parent_types: "Team", base: "Player"},
              valid_args_result: "TeamPlayerSubAggregation"
            }
          end

          describe "the SubAggregations format" do
            include_examples "a TypeNamer format", {
              format_name: :SubAggregations,
              valid_args: {parent_agg_type: "TeamAggregation", field_path: "Player"},
              valid_args_result: "TeamAggregationPlayerSubAggregations"
            }
          end

          describe "an unknown format" do
            it "raises a clear error when asked to generate a name for an unknown format" do
              expect {
                generate_name_for(:FiltreInput, base: "Widget")
              }.to raise_error Errors::ConfigError, "Unknown format name: :FiltreInput. Possible alternatives: :FilterInput."
            end

            it "raises a clear error when instantiated with an unknown format override" do
              expect_instantiation_config_error(
                "Unknown format name: :FiltreInput. Possible alternatives: :FilterInput.",
                FiltreInput: "%{base}Filtre"
              )
            end
          end

          describe "properties of an overall schema (using the full test schema for completeness)" do
            attr_reader :schema
            before(:context) do
              @schema = ::GraphQL::Schema.from_definition(CommonSpecHelpers.stock_schema_artifacts.graphql_schema_string)
            end

            let(:input_types) { schema.types.values.select { |type| type.kind.input_object? } }

            it "names all input object types with an `Input` suffix" do
              expect(input_types.size).to be > 10
              expect(input_types.map(&:graphql_name).grep_v(/Input\z/)).to be_empty
            end

            it "uses an `Input`-suffixed enum type for all enum arguments of an input object type" do
              input_object_arguments = input_types.flat_map do |input_type|
                input_type.arguments.values
              end

              expect_input_suffix_on_all_enum_arg_types(input_object_arguments)
            end

            it "uses an `Input`-suffixed enum type for all enum arguments of fields of all return types" do
              return_types_with_fields = schema.types.values.select { |type| type.kind.fields? }
              return_type_field_arguments = return_types_with_fields.flat_map do |type|
                type.fields.values.flat_map { |field| field.arguments.values }
              end

              expect_input_suffix_on_all_enum_arg_types(return_type_field_arguments)
            end

            def expect_input_suffix_on_all_enum_arg_types(arguments)
              enum_args = arguments.select { |arg| arg.type.unwrap.kind.enum? }
              expect(enum_args.size).to be > 5 # verify we have some, and not just 1 or 2...

              arg_def_sdls = enum_args.map { |arg| "#{arg.path}: #{arg.type.to_type_signature}" }
              expect(arg_def_sdls.grep_v(/Input[!\]]*\z/)).to be_empty
            end
          end

          def generate_name_for(format, overrides: {}, **args)
            namer = TypeNamer.new(format_overrides: overrides)
            namer.generate_name_for(format, **args)
          end

          def expect_instantiation_config_error(*problems, **overrides)
            expect {
              TypeNamer.new(format_overrides: overrides)
            }.to raise_error Errors::ConfigError, a_string_including(
              "Provided derived type name formats have #{problems.size} problem(s)",
              *problems
            )
          end

          def expect_generate_name_error(format_name, error_suffix, **args)
            default_format = TypeNamer::DEFAULT_FORMATS.fetch(format_name)

            expect {
              generate_name_for(format_name, **args)
            }.to raise_error(
              Errors::ConfigError,
              %(The arguments (#{args.inspect}) provided for `#{format_name}` format ("#{default_format}") #{error_suffix}.)
            )
          end
        end
      end
    end
  end
end
