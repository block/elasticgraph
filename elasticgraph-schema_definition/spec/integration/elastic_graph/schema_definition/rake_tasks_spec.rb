# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "bundler"
require "elastic_graph/constants"
require "elastic_graph/schema_definition/rake_tasks"
require "elastic_graph/schema_definition/schema_elements/type_namer"
require "graphql"
require "yaml"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe RakeTasks, :rake_task do
      describe "schema_artifacts:dump", :in_temp_dir do
        it "idempotently dumps all schema artifacts, and is able to check if they are current with `:check`" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          expect_all_artifacts_out_of_date_because_they_havent_been_dumped

          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", DATASTORE_CONFIG_FILE),
              a_string_including("Dumped", RUNTIME_METADATA_FILE),
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(1)),
              a_string_including("Dumped", GRAPHQL_SCHEMA_FILE)
            )
          }.to change { read_artifact(DATASTORE_CONFIG_FILE) }
            .from(a_falsy_value)
            # we expect `number_of_shards: 5` instead of `number_of_shards: 3` because the env-specific
            # overrides specified in the config YAML files should not influence the dumped artifacts.
            # We don't dump separate artifacts per environment, and thus shouldn't include overrides.
            .to(a_string_including("components:", "number_of_shards: 5", "update_ComponentDesigner_from_Component"))
            .and change { read_artifact(RUNTIME_METADATA_FILE) }
            .from(a_falsy_value)
            .to(a_string_including("script_id: update_ComponentDesigner_from_Component_").and(excluding("ruby/object")))
            .and change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_falsy_value)
            .to(a_string_including("\n  Component:", "\njson_schema_version: 1"))
            .and change { read_artifact(GRAPHQL_SCHEMA_FILE) }
            .from(a_falsy_value)
            .to(a_string_including("type Component {", "directive @fromExtensionModule"))

          # Verify the data is dumped in Alphabetical order for consistency, and is pruned
          # (Except for `EVENT_ENVELOPE_JSON_SCHEMA_NAME` -- it goes first).
          definition_names = YAML.safe_load(read_artifact(JSON_SCHEMAS_FILE)).fetch("$defs").keys
          expect(definition_names).to eq(%w[ElasticGraphEventEnvelope Component ElectricalPart ID MechanicalPart Size String])
          expect(YAML.safe_load(read_artifact(DATASTORE_CONFIG_FILE)).fetch("indices").keys).to eq %w[
            component_designers components electrical_parts mechanical_parts
          ]

          expect_up_to_date_artifacts

          # It should not write anything new, because the core contents have not changed.
          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(a_string_including("already up to date"))
          }.to maintain { read_artifact(DATASTORE_CONFIG_FILE) }
            .and maintain { read_artifact(RUNTIME_METADATA_FILE) }
            .and maintain { read_artifact(JSON_SCHEMAS_FILE) }
            .and maintain { read_artifact(GRAPHQL_SCHEMA_FILE) }

          write_elastic_graph_schema_def_code(component_suffix: "2", component_extras: "schema.deleted_type 'Component'", json_schema_version: 2)

          expect_out_of_date_artifacts_with_details(<<~EOS.strip)
            -  component_designers:
            +  component_designers2:
          EOS

          expect_out_of_date_artifacts_with_details(<<~EOS.strip, test_color: true)
            \e[31m-  component_designers:\e[m
            \e[32m+\e[m\e[32m  component_designers2:\e[m
          EOS

          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", DATASTORE_CONFIG_FILE),
              a_string_including("Dumped", RUNTIME_METADATA_FILE),
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(1)),
              a_string_including("Dumped", versioned_json_schema_file(2)),
              a_string_including("Dumped", GRAPHQL_SCHEMA_FILE)
            )
          }.to change { read_artifact(DATASTORE_CONFIG_FILE) }
            .from(a_string_including("components:", "update_ComponentDesigner_from_Component"))
            # we expect `number_of_shards: 5` instead of `number_of_shards: 3` because the env-specific
            # overrides specified in the config YAML files should not influence the dumped artifacts.
            # We don't dump separate artifacts per environment, and thus shouldn't include overrides.
            .to(a_string_including("components2:", "number_of_shards: 5", "update_ComponentDesigner2_from_Component2").and(excluding("components:", "update_ComponentDesigner_from_Component")))
            .and change { read_artifact(RUNTIME_METADATA_FILE) }
            .from(a_string_including("script_id: update_ComponentDesigner_from_Component_"))
            .to(a_string_including("script_id: update_ComponentDesigner2_from_Component2_"))
            .and change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_string_including("\n  Component:", "\njson_schema_version: 1"))
            .to(a_string_including("\n  Component2:", "\njson_schema_version: 2").and(excluding("\n  Component:")))
            .and change { read_artifact(GRAPHQL_SCHEMA_FILE) }
            .from(a_string_including("type Component {"))
            .to(a_string_including("type Component2 {").and(excluding("Component ")))

          expect_up_to_date_artifacts

          delete_artifact versioned_json_schema_file(2)
          expect_missing_versioned_json_schema_artifact "v2.yaml"
        end

        it "throws an error if the json_schemas artifact is (attempted to be) changed without json_schema_version being bumped" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          expect_all_artifacts_out_of_date_because_they_havent_been_dumped

          # Should succeed, for first artifact.
          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(1))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 1\n"))
            .and change { read_artifact(versioned_json_schema_file(1)) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 1\n"))

          expect_up_to_date_artifacts

          write_elastic_graph_schema_def_code(json_schema_version: 2)

          # Should succeed, it is ok to update the schema_version without underlying contents changing.
          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(2))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_string_including("\njson_schema_version: 1"))
            .to(a_string_including("\njson_schema_version: 2"))
            .and change { read_artifact(versioned_json_schema_file(2)) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 2\n"))

          write_elastic_graph_schema_def_code(component_suffix: "2", json_schema_version: 2, component_extras: "t.renamed_from 'Component'")
          expect_out_of_date_artifacts

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "A change has been attempted to `json_schemas.yaml`",
            "`schema.json_schema_version 3`"
          ).and matching(json_schema_version_setter_location_regex)

          # Still out of date.
          expect_out_of_date_artifacts

          # Decreasing the json_schema_version should also result in a failure.
          write_elastic_graph_schema_def_code(component_suffix: "2", json_schema_version: 1, component_extras: "t.renamed_from 'Component'")
          expect_out_of_date_artifacts

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "A change has been attempted to `json_schemas.yaml`",
            "`schema.json_schema_version 3`"
          ).and matching(json_schema_version_setter_location_regex)

          write_elastic_graph_schema_def_code(component_suffix: "2", json_schema_version: 3, component_extras: "t.renamed_from 'Component'")

          # Now dump should succeed, as schema_version has been bumped.
          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(3))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .from(a_string_including("\njson_schema_version: 2"))
            .to(a_string_including("\njson_schema_version: 3"))
            .and change { read_artifact(versioned_json_schema_file(3)) }
            .from(a_falsy_value)
            .to(a_string_including("\njson_schema_version: 3\n"))

          # Should be able to run `schema_artifacts:dump` idempotently.
          output = run_rake("schema_artifacts:dump")
          expect(output.lines).to include(
            a_string_including("is already up to date", JSON_SCHEMAS_FILE),
            a_string_including("is already up to date", versioned_json_schema_file(3))
          )

          write_elastic_graph_schema_def_code(component_suffix: "3", json_schema_version: 3, component_extras: "t.renamed_from 'Component'")
          expect_out_of_date_artifacts

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with a_string_including(
            "A change has been attempted to `json_schemas.yaml`",
            "`schema.json_schema_version 4`"
          ).and matching(json_schema_version_setter_location_regex)

          expect {
            output = run_rake("schema_artifacts:dump", enforce_json_schema_version: false)
            expect(output.lines).to include(
              a_string_including("Dumped", JSON_SCHEMAS_FILE),
              a_string_including("Dumped", versioned_json_schema_file(3))
            )
          }.to change { read_artifact(JSON_SCHEMAS_FILE) }
            .and change { read_artifact(versioned_json_schema_file(3)) }
        end

        it "allows the derived GraphQL type name formats to be customized" do
          # Disable documentation comment wrapping that the GraphQL gem does when formatting an SDL string.
          # We need to disable it because the customized derived type formats used below change the length
          # of comment lines and cause the documentation to wrap at different points, making it hard to
          # compare SDL strings below.
          allow(::GraphQL::Language::BlockString).to receive(:break_line) do |line, length, &block|
            block.call(line)
          end

          write_elastic_graph_schema_def_code(json_schema_version: 1)
          run_rake("schema_artifacts:dump")

          # We strip the comment preamble so we can compare it with an SDL string that lacks it below.
          uncustomized_graphql_schema = read_artifact(GRAPHQL_SCHEMA_FILE).sub(/^(#[^\n]+\n)+/, "").strip

          derived_type_name_formats = SchemaElements::TypeNamer::DEFAULT_FORMATS.transform_values do |format|
            "Prefix#{format}"
          end

          run_rake(
            "schema_artifacts:dump",
            derived_type_name_formats: derived_type_name_formats,
            type_name_overrides: {
              PrefixComponentGroupedBy: "PrefixComponentGroupedBy457"
            }
          )

          customized_graphql_schema = read_artifact(GRAPHQL_SCHEMA_FILE)

          # Our overrides should have added `Prefix` types, where non existed before...
          expect(uncustomized_graphql_schema.scan(/\bPrefix\w+\b/)).to be_empty
          expect(customized_graphql_schema.scan(/\bPrefix\w+\b/)).not_to be_empty

          # ...and completely renamed the `ComponentGroupedBy` type...
          expect(uncustomized_graphql_schema.scan(/\bComponentGroupedBy\b/)).not_to be_empty
          expect(customized_graphql_schema.scan(/\bComponentGroupedBy\b/)).to be_empty

          # ...to `PrefixComponentGroupedBy457`.
          expect(uncustomized_graphql_schema.scan(/\bPrefixComponentGroupedBy457\b/)).to be_empty
          expect(customized_graphql_schema.scan(/\bPrefixComponentGroupedBy457\b/)).not_to be_empty

          unprefixed_schema = ::GraphQL::Schema.from_definition(
            customized_graphql_schema
              .gsub("PrefixComponentGroupedBy457", "PrefixComponentGroupedBy")
              .gsub(/\b(?:Prefix)+(\w+)\b/) { |t| $1 }
          ).to_definition.strip

          expect(unprefixed_schema).to eq(uncustomized_graphql_schema)
        end

        it "generates separate input vs output enums by default, but allows them to be the same if desired" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)

          run_rake("schema_artifacts:dump")
          expect(enum_types_in_dumped_graphql_schema).to contain_exactly(
            "ComponentDesignerSortOrderInput",
            "ComponentSortOrderInput",
            "ElectricalPartSortOrderInput",
            "MechanicalPartSortOrderInput",
            "PartSortOrderInput",
            "Size",
            "SizeInput"
          )

          run_rake("schema_artifacts:dump", derived_type_name_formats: {InputEnum: "%{base}"})
          expect(enum_types_in_dumped_graphql_schema).to contain_exactly(
            "ComponentDesignerSortOrder",
            "ComponentSortOrder",
            "ElectricalPartSortOrder",
            "MechanicalPartSortOrder",
            "PartSortOrder",
            "Size"
          )
        end

        does_not_match_warning_snippet = "does not match any type in your GraphQL schema"

        it "respects type name overrides for all types (both core and derived), except standard GraphQL ones like `Int`" do
          original_types = graphql_types_defined_in(CommonSpecHelpers.stock_schema_artifacts(for_context: :graphql).graphql_schema_string)

          # In this test, we evaluate our main test schema because it exercises such a wide variety of cases.
          ::File.write("schema.rb", <<~EOS)
            load "#{CommonSpecHelpers::REPO_ROOT}/config/schema.rb"
          EOS

          exclusions = SchemaElements::TypeNamer::TYPES_THAT_CANNOT_BE_OVERRIDDEN
          expect(original_types).to include(*exclusions.to_a)
          overrides = (original_types - exclusions.to_a).to_h { |name| [name, "Pre#{name}"] }

          output = run_rake(
            "schema_artifacts:dump",
            type_name_overrides: overrides.merge({"Widgets" => "Unused"}),
            enum_value_overrides_by_type: {
              "PreColor" => {"GREAN" => "GREENISH", "MAGENTA" => "RED"},
              "DateGroupingTruncationUnitInput" => {"DAY" => "DAILY"},
              "Nonsense" => {"FOO" => "BAR"}
            }
          )

          expect(output).to match(
            /WARNING: \d+ of the `type_name_overrides` do not match any type\(s\) in your GraphQL schema/
          ).and include(
            "The type name override `Widgets` #{does_not_match_warning_snippet} and has been ignored. Possible alternatives: `Widget`"
          )

          expect(output[/WARNING: some of the `enum_value_overrides_by_type`.*\z/m].lines.first(6).join).to eq(<<~EOS)
            WARNING: some of the `enum_value_overrides_by_type` do not match any type(s)/value(s) in your GraphQL schema:

            1. The enum value override `PreColor.GREAN` does not match any enum value in your GraphQL schema and has been ignored. Possible alternatives: `GREEN`.
            2. The enum value override `PreColor.MAGENTA` does not match any enum value in your GraphQL schema and has been ignored.
            3. `enum_value_overrides_by_type` has a `DateGroupingTruncationUnitInput` key, which does not match any enum type in your GraphQL schema and has been ignored. Possible alternatives: `PreDateGroupingTruncationUnitInput`, `DateGroupingTruncationUnit`.
            4. `enum_value_overrides_by_type` has a `Nonsense` key, which does not match any enum type in your GraphQL schema and has been ignored.
          EOS

          overriden_types = graphql_types_defined_in(read_artifact(GRAPHQL_SCHEMA_FILE))

          # We should have lots of types starting with `Pre`...
          expect(overriden_types.grep(/\APre[A-Z]/).size).to be > 50
          # ...and the only types that do not start with `Pre` should be our standard exclusions.
          expect(overriden_types.grep_v(/\APre[A-Z]/)).to match_array(exclusions)
        end

        it "respects type name overrides for all core types (excluding derived types), except standard GraphQL ones like `Int`" do
          derived_type_suffixes = SchemaElements::TypeNamer::DEFAULT_FORMATS.values.map do |format|
            format.split("}").last
          end
          derived_type_regex = /#{derived_type_suffixes.join("|")}\z/

          exclusions = SchemaElements::TypeNamer::TYPES_THAT_CANNOT_BE_OVERRIDDEN
          schema_string = CommonSpecHelpers.stock_schema_artifacts(for_context: :graphql).graphql_schema_string
          original_core_types = graphql_types_defined_in(schema_string).reject do |t|
            t.start_with?("__") || derived_type_regex.match?(t) || exclusions.include?(t)
          end

          # In this test, we evaluate our main test schema because it exercises such a wide variety of cases.
          ::File.write("schema.rb", <<~EOS)
            load "#{CommonSpecHelpers::REPO_ROOT}/config/schema.rb"
          EOS

          overrides = original_core_types.to_h { |name| [name, "Pre#{name}"] }

          output = run_rake("schema_artifacts:dump", type_name_overrides: overrides)
          expect(output).to exclude(does_not_match_warning_snippet)

          overriden_types = graphql_types_defined_in(read_artifact(GRAPHQL_SCHEMA_FILE))

          # We should have lots of types starting with `Pre`...
          expect(overriden_types.grep(/\APre[A-Z]/).size).to be > 50
          # ...and almost no types that do not start with `Pre`: just the exclusions, types derived from them, and a few others.
          filtered_types = overriden_types.grep_v(/\APre[A-Z]/).grep_v(/\A(#{exclusions.join("|")})/)
          allowed_list = %w[
            AggregationCountDetail
            DateGroupedBy DateGroupingOffsetInput DateGroupingTruncationUnitInput
            DateTimeGroupedBy DateTimeGroupingOffsetInput DateTimeGroupingTruncationUnitInput
            DateTimeUnitInput DateUnitInput
            DayOfWeekGroupingOffsetInput
            LocalTimeGroupingOffsetInput LocalTimeGroupingTruncationUnitInput LocalTimeUnitInput
            NonNumericAggregatedValues TextFilterInput
            MatchesQueryFilterInput MatchesQueryAllowedEditsPerTermInput MatchesPhraseFilterInput
          ]

          expect(filtered_types).to match_array(allowed_list)
        end

        it "dumps the ElasticGraph JSON schema metadata only on the internal versioned JSON schema, omitting it from the public copy" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          run_rake("schema_artifacts:dump")

          expect(::YAML.safe_load(read_artifact(JSON_SCHEMAS_FILE)).dig("$defs", "Component", "properties", "id")).to eq(
            json_schema_for_keyword_type("ID")
          )

          expect(::YAML.safe_load(read_artifact(versioned_json_schema_file(1))).dig("$defs", "Component", "properties", "id")).to eq(
            json_schema_for_keyword_type("ID", {
              "ElasticGraph" => {
                "type" => "ID!",
                "nameInIndex" => "id"
              }
            })
          )
        end

        it "keeps the ElasticGraph JSON schema metadata up-to-date on all versioned JSON schemas" do
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          run_rake("schema_artifacts:dump")

          expect(::YAML.safe_load(read_artifact(versioned_json_schema_file(1))).dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name"
              }
            })
          )

          # Here we add a new field `another: String`
          write_elastic_graph_schema_def_code(json_schema_version: 2, component_name_extras: "\nt.field 'another', 'String!'")
          run_rake("schema_artifacts:dump")

          # It's not added to v1.yaml...
          loaded_v1 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(1)))
          expect(loaded_v1.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name"
              }
            })
          )
          expect(loaded_v1.dig("$defs", "Component", "properties", "another")).to eq(nil)

          # ..but is added to v2.yaml.
          loaded_v2 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(2)))
          expect(loaded_v2.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name"
              }
            })
          )
          expect(loaded_v2.dig("$defs", "Component", "properties", "another")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "another"
              }
            })
          )

          # Here we keep the newly added field `another: String` and also change the `name_in_index` of `name`.
          write_elastic_graph_schema_def_code(json_schema_version: 2, component_name_extras: ", name_in_index: 'name2'\nt.field 'another', 'String!'")
          run_rake("schema_artifacts:dump")

          # The `name_in_index` for `name` should be changed to `name2` in the v1 schema...
          loaded_v1 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(1)))
          expect(loaded_v1.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name2"
              }
            })
          )
          expect(loaded_v1.dig("$defs", "Component", "properties", "another")).to eq(nil)

          # ...and in the v1 schema.
          loaded_v2 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(2)))
          expect(loaded_v2.dig("$defs", "Component", "properties", "name")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "name2"
              }
            })
          )
          expect(loaded_v2.dig("$defs", "Component", "properties", "another")).to eq(
            json_schema_for_keyword_type("String", {
              "ElasticGraph" => {
                "type" => "String!",
                "nameInIndex" => "another"
              }
            })
          )

          # Here we add a different new field (`ordinal: Int!`), without bumping the version (and using `enforce_json_schema_version: false`
          # to not have to bump the version)...
          write_elastic_graph_schema_def_code(json_schema_version: 2, component_name_extras: "\nt.field 'ordinal', 'Int!'")
          run_rake("schema_artifacts:dump", enforce_json_schema_version: false)

          # It should not be added to the v1 schema...
          loaded_v1 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(1)))
          expect(loaded_v1.dig("$defs", "Component", "properties", "ordinal")).to eq(nil)

          # ...but it should be added to the v2 schema.
          loaded_v2 = ::YAML.safe_load(read_artifact(versioned_json_schema_file(2)))
          expect(loaded_v2.dig("$defs", "Component", "properties", "ordinal")).to eq({
            "$ref" => "#/$defs/Int",
            "ElasticGraph" => {"type" => "Int!", "nameInIndex" => "ordinal"}
          })
        end

        it "gives the user a clear error when there is ambiguity about what to do with a renamed or deleted field" do
          # Verify the error message with 1 old JSON schema version (v8).
          write_elastic_graph_schema_def_code(json_schema_version: 8)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 9, omit_component_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component.name` field (which existed in JSON schema version 8) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this field's data when ingesting events at this old version.
            To continue, do one of the following:

            1. If the `Component.name` field has been renamed, indicate this by calling `field.renamed_from "name"` on the renamed field.
            2. If the `Component.name` field has been dropped, indicate this by calling `type.deleted_field "name"` on the `Component` type.
            3. Alternately, if no publishers or in-flight events use JSON schema version 8, delete its file from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 2 old JSON schema version (v8 and v9).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 8 and 9").
          write_elastic_graph_schema_def_code(json_schema_version: 9)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 10, omit_component_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component.name` field (which existed in JSON schema versions 8 and 9) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this field's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component.name` field has been renamed, indicate this by calling `field.renamed_from "name"` on the renamed field.
            2. If the `Component.name` field has been dropped, indicate this by calling `type.deleted_field "name"` on the `Component` type.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 8 or 9, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 3 old JSON schema version (v8, v9, and v10).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 8, 9, and 10").
          write_elastic_graph_schema_def_code(json_schema_version: 10)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true)
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component.name` field (which existed in JSON schema versions 8, 9, and 10) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this field's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component.name` field has been renamed, indicate this by calling `field.renamed_from "name"` on the renamed field.
            2. If the `Component.name` field has been dropped, indicate this by calling `type.deleted_field "name"` on the `Component` type.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 8, 9, or 10, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Demonstrate that these issues can be solved by each of the 3 options given.
          # First, demonstrate indicating the field has been renamed.
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true, component_extras: "t.field('full_name', 'String') { |f| f.renamed_from 'name' }")
          run_rake("schema_artifacts:dump")
          delete_artifact(JSON_SCHEMAS_FILE) # so it doesn't force us to increment the version to 5

          # Next, demonstrate indicating the field has been deleted.
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true, component_extras: "t.deleted_field 'name'")
          run_rake("schema_artifacts:dump")

          # Finally, demonstrate deleting the old JSON schema version artifacts
          delete_artifact(versioned_json_schema_file(8))
          delete_artifact(versioned_json_schema_file(9))
          delete_artifact(versioned_json_schema_file(10))
          write_elastic_graph_schema_def_code(json_schema_version: 11, omit_component_name_field: true)
          run_rake("schema_artifacts:dump")
        end

        it "gives the user a clear error when there is ambiguity about what to do with a renamed or deleted type" do
          # Verify the error message with 1 old JSON schema version (v1).
          write_elastic_graph_schema_def_code(json_schema_version: 1)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 2, component_suffix: "2")
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component` type (which existed in JSON schema version 1) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this type's data when ingesting events at this old version.
            To continue, do one of the following:

            1. If the `Component` type has been renamed, indicate this by calling `type.renamed_from "Component"` on the renamed type.
            2. If the `Component` field has been dropped, indicate this by calling `schema.deleted_type "Component"` on the schema.
            3. Alternately, if no publishers or in-flight events use JSON schema version 1, delete its file from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 2 old JSON schema version (v1 and v2).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 1 and 2").
          write_elastic_graph_schema_def_code(json_schema_version: 2)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 3, component_suffix: "2")
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component` type (which existed in JSON schema versions 1 and 2) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this type's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component` type has been renamed, indicate this by calling `type.renamed_from "Component"` on the renamed type.
            2. If the `Component` field has been dropped, indicate this by calling `schema.deleted_type "Component"` on the schema.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 1 or 2, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Verify the error message with 3 old JSON schema version (v1, v2, and v3).
          # The grammar/phrasing is adjusted slightly (e.g. "versions 1, 2, and 3").
          write_elastic_graph_schema_def_code(json_schema_version: 3)
          run_rake("schema_artifacts:dump")
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2")
          expect { run_rake("schema_artifacts:dump") }.to abort_with <<~EOS
            The `Component` type (which existed in JSON schema versions 1, 2, and 3) no longer exists in the current schema definition.
            ElasticGraph cannot guess what it should do with this type's data when ingesting events at these old versions.
            To continue, do one of the following:

            1. If the `Component` type has been renamed, indicate this by calling `type.renamed_from "Component"` on the renamed type.
            2. If the `Component` field has been dropped, indicate this by calling `schema.deleted_type "Component"` on the schema.
            3. Alternately, if no publishers or in-flight events use JSON schema versions 1, 2, or 3, delete their files from `json_schemas_by_version`, and no further changes are required.
          EOS

          # Demonstrate that these issues can be solved by each of the 3 options given.
          # First, demonstrate indicating the type has been renamed.
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2", component_extras: "t.renamed_from 'Component'")
          run_rake("schema_artifacts:dump")
          delete_artifact(JSON_SCHEMAS_FILE) # so it doesn't force us to increment the version to 5

          # Next, demonstrate indicating the type has been deleted.
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2", component_extras: "schema.deleted_type 'Component'")
          run_rake("schema_artifacts:dump")

          # Finally, demonstrate deleting the old JSON schema version artifacts
          delete_artifact(versioned_json_schema_file(1))
          delete_artifact(versioned_json_schema_file(2))
          delete_artifact(versioned_json_schema_file(3))
          write_elastic_graph_schema_def_code(json_schema_version: 4, component_suffix: "2")
          run_rake("schema_artifacts:dump")
        end

        it "warns if there are `deleted_*` or `renamed_from` calls that are not needed so the user knows they can remove them" do
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1
              schema.deleted_type "SomeType"

              schema.object_type "Widget" do |t|
                t.renamed_from "Widget2"
                t.deleted_field "name"
                t.field "description", "String" do |f|
                  f.renamed_from "old_description"
                end
                t.renamed_from "Widget3"

                t.field "id", "ID"
                t.index "widgets"
              end
            end
          EOS

          output = run_rake("schema_artifacts:dump")
          expect(output.split("\n").first(9).join("\n")).to eq(<<~EOS.strip)
            The schema definition has 5 unneeded reference(s) to deprecated schema elements. These can all be safely deleted:

            1. `schema.deleted_type "SomeType"` at schema.rb:3
            2. `type.renamed_from "Widget2"` at schema.rb:6
            3. `type.deleted_field "name"` at schema.rb:7
            4. `field.renamed_from "old_description"` at schema.rb:9
            5. `type.renamed_from "Widget3"` at schema.rb:11

            Dumped schema artifact to `config/schema/artifacts/datastore_config.yaml`.
          EOS
        end

        it "gives a clear error if excess `deleted_*` or `renamed_from` calls create a conflict" do
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1
              schema.deleted_type "Widget"

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.index "widgets"

                t.field "token", "ID" do |f|
                  f.renamed_from "id"
                end
                t.deleted_field "id"
              end
            end
          EOS

          expect {
            run_rake("schema_artifacts:dump")
          }.to abort_with(<<~EOS)
            The schema definition of `Widget` has conflicts. To resolve the conflict, remove the unneeded definitions from the following:

            1. `schema.deleted_type "Widget"` at schema.rb:3


            The schema definition of `Widget.id` has conflicts. To resolve the conflict, remove the unneeded definitions from the following:

            1. `field.renamed_from "id"` at schema.rb:10
            2. `type.deleted_field "id"` at schema.rb:12
          EOS
        end

        it "does not allow a routing or rollover field to be deleted since we cannot index documents without values for those fields" do
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "Embedded" do |t|
                t.field "workspace_id", "ID"
                t.field "created_at", "DateTime"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "embedded", "Embedded"
                t.index "widgets" do |i|
                  i.route_with "embedded.workspace_id"
                  i.rollover :yearly, "embedded.created_at"
                end
              end
            end
          EOS

          run_rake("schema_artifacts:dump")

          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 2

              schema.object_type "Embedded" do |t|
                t.field "workspace_id2", "ID", name_in_index: "workspace_id"
                t.deleted_field "workspace_id"

                t.field "created_at2", "DateTime", name_in_index: "created_at"
                t.deleted_field "created_at"
              end

              schema.object_type "Widget" do |t|
                t.field "id", "ID"
                t.field "embedded", "Embedded"
                t.index "widgets" do |i|
                  i.route_with "embedded.workspace_id2"
                  i.rollover :yearly, "embedded.created_at2"
                end
              end
            end
          EOS

          expect { run_rake("schema_artifacts:dump") }.to abort_with(<<~EOS)
            JSON schema version 1 has no field that maps to the routing field path of `Widget.embedded.workspace_id`.
            Since the field path is required for routing, ElasticGraph cannot ingest events that lack it. To continue, do one of the following:

            1. If the `Widget.embedded.workspace_id` field has been renamed, indicate this by calling `field.renamed_from "workspace_id"` on the renamed field rather than using `deleted_field`.
            2. Alternately, if no publishers or in-flight events use JSON schema version 1, delete its file from `json_schemas_by_version`, and no further changes are required.


            JSON schema version 1 has no field that maps to the rollover field path of `Widget.embedded.created_at`.
            Since the field path is required for rollover, ElasticGraph cannot ingest events that lack it. To continue, do one of the following:

            1. If the `Widget.embedded.created_at` field has been renamed, indicate this by calling `field.renamed_from "created_at"` on the renamed field rather than using `deleted_field`.
            2. Alternately, if no publishers or in-flight events use JSON schema version 1, delete its file from `json_schemas_by_version`, and no further changes are required.
          EOS
        end

        it "does not change the formatting of the dumped artifacts in unexpected ways" do
          config_dir = File.join(CommonSpecHelpers::REPO_ROOT, "config")
          run_rake("schema_artifacts:dump", path_to_schema: File.join(config_dir, "schema.rb"), include_extension_module: false)

          # :nocov: -- some branches below depend on pass vs fail or local vs CI.
          diff = `git diff --no-index #{File.join(config_dir, "schema", "artifacts")} config/schema/artifacts #{"--color" if $stdout.tty?}`

          unless diff == ""
            RSpec.world.reporter.message("\n\nThe schema artifact diff:\n\n#{diff}")

            fail <<~EOS
              Expected no formatting changes to the test/development schema artifacts, but there are some. If this is by design,
              please delete and re-dump the artifacts with differences to bring our local artifacts up to date with the current
              formatting. See "The schema artifact diff:" above for details.
            EOS
          end
          # :nocov:
        end

        it "retains `extend schema` in the dumped SDL if ElasticGraph includes it in the generated SDL string" do
          write_elastic_graph_schema_def_code(json_schema_version: 1, extra_sdl: "")
          run_rake("schema_artifacts:dump")

          # `extend` should not be added by default...
          expect(read_artifact(GRAPHQL_SCHEMA_FILE)).not_to include("extend")

          write_elastic_graph_schema_def_code(json_schema_version: 1, extra_sdl: <<~EOS)
            extend schema
              @customDirective

            directive @customDirective repeatable on SCHEMA
          EOS
          run_rake("schema_artifacts:dump")

          # ...but it should be added when there's a schema that's been generated.
          expect(read_artifact(GRAPHQL_SCHEMA_FILE).lines[3]).to eq("extend schema\n")
        end

        it "omits unreferenced GraphQL types from the dumped runtime metadata" do
          runtime_meta = runtime_metadata_for_elastic_graph_schema_def_code(include_date_time_fields: true)
          expect(runtime_meta["scalar_types_by_name"].keys).to include("DateTime")
          expect(runtime_meta["enum_types_by_name"].keys).to include("DateTimeGroupingTruncationUnitInput")
          expect(runtime_meta["object_types_by_name"].keys).to include("DateTimeListFilterInput")

          runtime_meta = runtime_metadata_for_elastic_graph_schema_def_code(include_date_time_fields: false)
          expect(runtime_meta["scalar_types_by_name"].keys).to exclude("DateTime")
          expect(runtime_meta["enum_types_by_name"].keys).to exclude("DateTimeGroupingTruncationUnitInput")
          expect(runtime_meta["object_types_by_name"].keys).to exclude("DateTimeListFilterInput")
        end

        it "successfully checks schema artifacts when the rake task is run within a bundle that only includes the `elasticgraph-schema_definition` gem" do
          # We want to ensure that `elasticgraph-schema_definition` gem declares (in its gemspec) all the
          # dependencies necessary for the schema definition rake tasks. Unfortunately, it's test suite
          # alone can't detect this, even when run via `script/run_gem_specs`, due to transitive dependencies
          # of some of the test dependencies. For example, in January 2023, `elasticgraph-schema_definition`
          # began needing parts of `elasticgraph-indexer` at run time, but we forgot to add it to the gemspec,
          # and `elasticgraph-admin` is a test dependency, which transitively pulls in `elasticgraph-indexer`.
          #
          # Here we verify the dependencies by creating a standalone Gemfile and Rakefile in a tmp directory
          # that just depends on the runtime deps of `elasticgraph-schema_definition` (and the runtime deps
          # of those, recursively).
          ::File.write("Gemfile", <<~EOS)
            source "https://rubygems.org"

            gem "elasticgraph-schema_definition", path: "#{CommonSpecHelpers::REPO_ROOT}/elasticgraph-schema_definition"

            register_gemspec_gems_with_path = lambda do |eg_gem_name|
              gemspec_contents = ::File.read("#{CommonSpecHelpers::REPO_ROOT}/\#{eg_gem_name}/\#{eg_gem_name}.gemspec")
              eg_deps = gemspec_contents.scan(/^\\s+spec\\.add_dependency "((?:elasticgraph-)\\w+)"/).flatten

              eg_deps.each do |dep|
                gem dep, path: "#{CommonSpecHelpers::REPO_ROOT}/\#{dep}"
                register_gemspec_gems_with_path.call(dep)
              end
            end

            register_gemspec_gems_with_path.call("elasticgraph-schema_definition")
          EOS

          ::File.write("Rakefile", <<~EOS)
            project_root = "#{CommonSpecHelpers::REPO_ROOT}"

            require "elastic_graph/schema_definition/rake_tasks"

            ElasticGraph::SchemaDefinition::RakeTasks.new(
              schema_element_name_form: :snake_case,
              index_document_sizes: true,
              path_to_schema: "\#{project_root}/config/schema.rb",
              schema_artifacts_directory: "\#{project_root}/config/schema/artifacts",
              enforce_json_schema_version: false
            )
          EOS

          ::FileUtils.cp("#{CommonSpecHelpers::REPO_ROOT}/Gemfile.lock", "Gemfile.lock")

          expect_successful_run_of(
            "bundle check || bundle install",
            "bundle show",
            "bundle exec rake schema_artifacts:check"
          )
        end

        def expect_successful_run_of(*shell_commands)
          outputs = []
          expect {
            ::Bundler.with_original_env do
              shell_commands.each do |command|
                outputs << `#{command} 2>&1`
                expect($?).to be_success, -> do
                  # :nocov: -- only covered when a test fails.
                  <<~EOS
                    Command `#{command}` failed with exit status #{$?.exitstatus}:

                    #{outputs.join("\n\n")}
                  EOS
                  # :nocov:
                end
              end
            end
          }.to output(/Your Gemfile lists/).to_stderr_from_any_process
        end

        let(:json_schema_version_setter_location_regex) do
          # In `write_elastic_graph_schema_def_code` `json_schema_version` is called on the 2nd line of
          # the file written to `schema.rb`. See below.
          #
          # Note: on Ruby 3.3, the path here winds up being slightly different; instead of just `schema.rb` it is something like:
          # `../d20240216-23551-cvdjzo/schema.rb`. I think it's related to the temp directory we run these specs within.
          /line 2 at `(\S*\/?)schema\.rb`/
        end

        def write_elastic_graph_schema_def_code(json_schema_version:, component_suffix: "", extra_sdl: "", component_name_extras: "", component_extras: "", omit_component_name_field: false)
          code = <<~EOS
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version #{json_schema_version}
              schema.enum_type "Size" do |t|
                t.values "SMALL", "MEDIUM", "LAGE"
              end

              schema.object_type "MechanicalPart" do |t|
                t.field "id", "ID!" do |f|
                  f.directive "fromExtensionModule"
                end

                t.index "mechanical_parts"
              end

              schema.object_type "ElectricalPart" do |t|
                t.field "id", "ID!"
                t.field "size", "Size"
                t.index "electrical_parts"
              end

              schema.union_type "Part" do |t|
                t.subtypes %w[MechanicalPart ElectricalPart]
              end

              schema.object_type "ComponentDesigner#{component_suffix}" do |t|
                t.field "id", "ID!"
                t.field "designed_component_names", "[String!]!"
                t.index "component_designers#{component_suffix}"
              end

              schema.object_type "Component#{component_suffix}" do |t|
                t.field "id", "ID!"
                #{%(t.field "name", "String!"#{component_name_extras}) unless omit_component_name_field}
                t.field "designer_id", "ID"
                t.index "components#{component_suffix}", number_of_shards: 5

                t.derive_indexed_type_fields "ComponentDesigner#{component_suffix}", from_id: "designer_id" do |derive|
                  derive.append_only_set "designed_component_names", from: "name"
                end
                #{component_extras}
              end

              schema.raw_sdl #{extra_sdl.inspect}
            end
          EOS

          ::File.write("schema.rb", code)
        end

        def runtime_metadata_for_elastic_graph_schema_def_code(include_date_time_fields:)
          ::File.write("schema.rb", <<~EOS)
            ElasticGraph.define_schema do |schema|
              schema.json_schema_version 1

              schema.object_type "MyType" do |t|
                t.field "id", "ID!"
                #{'t.field "timestamp", "DateTime"' if include_date_time_fields}
                #{'t.field "timestamps", "[DateTime]"' if include_date_time_fields}
                t.index "my_type"
              end
            end
          EOS

          run_rake("schema_artifacts:dump", enforce_json_schema_version: false)
          ::YAML.safe_load(read_artifact(RUNTIME_METADATA_FILE))
        end

        def expect_up_to_date_artifacts
          output = nil

          expect {
            output = run_rake("schema_artifacts:check")
          }.not_to raise_error

          expect(output).to include(DATASTORE_CONFIG_FILE, JSON_SCHEMAS_FILE, "up to date")
        end

        def expect_all_artifacts_out_of_date_because_they_havent_been_dumped
          expect {
            run_rake("schema_artifacts:check")
          }.to abort_with { |error|
            expect(error.message).to eq(<<~EOS.strip)
              5 schema artifact(s) are out of date. Run `rake schema_artifacts:dump` to update the following artifact(s):

              1. config/schema/artifacts/datastore_config.yaml (file does not exist)
              2. config/schema/artifacts/json_schemas.yaml (file does not exist)
              3. config/schema/artifacts/json_schemas_by_version/v1.yaml (file does not exist)
              4. config/schema/artifacts/runtime_metadata.yaml (file does not exist)
              5. config/schema/artifacts/schema.graphql (file does not exist)
            EOS
          }
        end

        def expect_missing_versioned_json_schema_artifact(version_file)
          expect {
            run_rake("schema_artifacts:check")
          }.to abort_with { |error|
            expect(error.message).to eq(<<~EOS.strip)
              1 schema artifact(s) are out of date. Run `rake schema_artifacts:dump` to update the following artifact(s):

              1. config/schema/artifacts/json_schemas_by_version/#{version_file} (file does not exist)
            EOS
          }
        end

        def expect_out_of_date_artifacts_with_details(example_diff, test_color: false)
          expect {
            run_rake("schema_artifacts:check", pretend_tty: test_color)
          }.to abort_with { |error|
            expect(error.message.lines.first(8).join).to eq(<<~EOS)
              6 schema artifact(s) are out of date. Run `rake schema_artifacts:dump` to update the following artifact(s):

              1. config/schema/artifacts/datastore_config.yaml (see [1] below for the diff)
              2. config/schema/artifacts/json_schemas.yaml (see [2] below for the first 50 lines of the diff)
              3. config/schema/artifacts/json_schemas_by_version/v1.yaml (see [3] below for the diff)
              4. config/schema/artifacts/json_schemas_by_version/v2.yaml (file does not exist)
              5. config/schema/artifacts/runtime_metadata.yaml (see [4] below for the first 50 lines of the diff)
              6. config/schema/artifacts/schema.graphql (see [5] below for the first 50 lines of the diff)
            EOS

            expect(error.message).to include(example_diff)
          }
        end

        def expect_out_of_date_artifacts
          expect {
            run_rake("schema_artifacts:check")
          }.to abort_with a_string_including("out of date", DATASTORE_CONFIG_FILE, JSON_SCHEMAS_FILE)
        end

        def read_artifact(name)
          path = File.join("config", "schema", "artifacts", name)
          File.exist?(path) && File.read(path)
        end

        def delete_artifact(*name_parts)
          ::File.delete(::File.join("config", "schema", "artifacts", *name_parts))
        end

        def versioned_json_schema_file(version)
          ::File.join(JSON_SCHEMAS_BY_VERSION_DIRECTORY, "v#{version}.yaml")
        end
      end

      def run_rake(
        *args,
        enforce_json_schema_version: true,
        pretend_tty: false,
        path_to_schema: "schema.rb",
        include_extension_module: true,
        derived_type_name_formats: {},
        type_name_overrides: {},
        enum_value_overrides_by_type: {}
      )
        if include_extension_module
          extension_module = Module.new do
            def as_active_instance
              raw_sdl "directive @fromExtensionModule on FIELD_DEFINITION"
              super
            end
          end
        end

        super(*args) do |output|
          allow(output).to receive(:tty?).and_return(true) if pretend_tty

          ElasticGraph::SchemaDefinition::RakeTasks.new(
            schema_element_name_form: :snake_case,
            index_document_sizes: true,
            path_to_schema: path_to_schema,
            schema_artifacts_directory: "config/schema/artifacts",
            enforce_json_schema_version: enforce_json_schema_version,
            extension_modules: [extension_module].compact,
            derived_type_name_formats: derived_type_name_formats,
            type_name_overrides: type_name_overrides,
            enum_value_overrides_by_type: enum_value_overrides_by_type,
            output: output
          )
        end
      end

      def json_schema_for_keyword_type(type, extras = {})
        {
          "allOf" => [
            {"$ref" => "#/$defs/#{type}"},
            {"maxLength" => DEFAULT_MAX_KEYWORD_LENGTH}
          ]
        }.merge(extras)
      end

      def enum_types_in_dumped_graphql_schema
        ::GraphQL::Schema.from_definition(read_artifact(GRAPHQL_SCHEMA_FILE)).types.filter_map do |name, type|
          name if type.kind.enum? && !name.start_with?("__")
        end.to_set
      end

      def graphql_types_defined_in(schema_string)
        ::GraphQL::Schema
          .from_definition(schema_string)
          .types
          .keys
          .reject { |t| t.start_with?("__") }
          .sort
      end
    end
  end
end
