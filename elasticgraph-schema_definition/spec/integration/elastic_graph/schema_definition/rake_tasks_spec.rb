# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "bundler"
require "elastic_graph/constants"
require "elastic_graph/json_ingestion/schema_definition/api_extension"
require "elastic_graph/schema_definition/rake_tasks"
require "elastic_graph/schema_definition/schema_elements/type_namer"
require "graphql"
require "yaml"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe RakeTasks, :rake_task do
      # JRuby has a bug (https://github.com/jruby/jruby/issues/9242) that causes spurious
      # "keyword arguments" warnings on stderr when `initialize(...)` + `super(...)` is used
      # in a module prepended on a Struct subclass. Our jruby_patches.rb works around this,
      # but a load-order regression can silently re-expose the warnings. This hook ensures
      # we catch that. We use `to_stderr_from_any_process` (fd-level) rather than `to_stderr`
      # ($stderr-level) because one test below nests `to_stderr_from_any_process` inside this.
      around do |example|
        expect { example.run }.not_to output(/./).to_stderr_from_any_process
      end

      after do
        Thread.current[:eg_schema_load_count] = nil
      end

      describe "schema_artifacts:dump", :in_temp_dir do
        it "idempotently dumps all schema artifacts, and is able to check if they are current with `:check`" do
          write_elastic_graph_schema_def_code
          expect_all_artifacts_out_of_date_because_they_havent_been_dumped

          expect {
            output = run_rake("schema_artifacts:dump")
            expect(output.lines).to include(
              a_string_including("Dumped", DATASTORE_CONFIG_FILE),
              a_string_including("Dumped", RUNTIME_METADATA_FILE),
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
            .and change { read_artifact(GRAPHQL_SCHEMA_FILE) }
            .from(a_falsy_value)
            .to(a_string_including("type Component {", "directive @fromExtensionModule"))

          # Verify the data is dumped in Alphabetical order for consistency.
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
            .and maintain { read_artifact(GRAPHQL_SCHEMA_FILE) }

          write_elastic_graph_schema_def_code(component_suffix: "2")

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
            .and change { read_artifact(GRAPHQL_SCHEMA_FILE) }
            .from(a_string_including("type Component {"))
            .to(a_string_including("type Component2 {").and(excluding("Component ")))

          expect_up_to_date_artifacts
        end

        it "shows the full diff for an out-of-date artifact when the diff is short" do
          write_elastic_graph_schema_def_code
          run_rake("schema_artifacts:dump")

          write_elastic_graph_schema_def_code(number_of_shards: 7)

          expect {
            run_rake("schema_artifacts:check")
          }.to abort_with { |error|
            expect(error.message)
              .to include("1. config/schema/artifacts/datastore_config.yaml (see [1] below for the diff)", "number_of_shards")
              .and exclude("lines of the diff")
          }
        end

        it "allows the derived GraphQL type name formats to be customized" do
          # Disable documentation comment wrapping that the GraphQL gem does when formatting an SDL string.
          # We need to disable it because the customized derived type formats used below change the length
          # of comment lines and cause the documentation to wrap at different points, making it hard to
          # compare SDL strings below.
          allow(::GraphQL::Language::BlockString).to receive(:break_line) do |line, length, &block|
            block.call(line)
          end

          write_elastic_graph_schema_def_code
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
          write_elastic_graph_schema_def_code

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
          original_types = graphql_types_defined_in(CommonSpecHelpers.stock_schema_artifacts.graphql_schema_string)

          # In this test, we evaluate our main test schema because it exercises such a wide variety of cases.
          ::File.write("schema.rb", <<~EOS)
            load "#{CommonSpecHelpers::REPO_ROOT}/config/schema.rb"
          EOS

          exclusions = SchemaElements::TypeNamer::TYPES_THAT_CANNOT_BE_OVERRIDDEN
          expect(original_types).to include(*exclusions.to_a)
          overrides = (original_types - exclusions.to_a).to_h { |name| [name, "Pre#{name}"] }

          output = run_rake(
            "schema_artifacts:dump",
            extension_modules: [JSONIngestion::SchemaDefinition::APIExtension],
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
          schema_string = CommonSpecHelpers.stock_schema_artifacts.graphql_schema_string
          original_core_types = graphql_types_defined_in(schema_string).reject do |t|
            t.start_with?("__") || derived_type_regex.match?(t) || exclusions.include?(t)
          end

          # In this test, we evaluate our main test schema because it exercises such a wide variety of cases.
          ::File.write("schema.rb", <<~EOS)
            load "#{CommonSpecHelpers::REPO_ROOT}/config/schema.rb"
          EOS

          overrides = original_core_types.to_h { |name| [name, "Pre#{name}"] }

          output = run_rake("schema_artifacts:dump", extension_modules: [JSONIngestion::SchemaDefinition::APIExtension], type_name_overrides: overrides)
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
            MatchesQueryFilterInput MatchesQueryAllowedEditsPerTermInput MatchesPhraseFilterInput MatchesQueryWithPrefixFilterInput
            WidgetInternalDetailsAggregatedValues WidgetInternalDetailsFilterInput WidgetInternalDetailsGroupedBy WidgetInternalDetailsHighlights
          ]

          expect(filtered_types).to match_array(allowed_list)
        end

        it "does not change the formatting of the dumped artifacts in unexpected ways" do
          config_dir = File.join(CommonSpecHelpers::REPO_ROOT, "config")
          run_rake(
            "schema_artifacts:dump",
            path_to_schema: File.join(config_dir, "schema.rb"),
            include_extension_module: false,
            extension_modules: [JSONIngestion::SchemaDefinition::APIExtension]
          )

          # :nocov: -- some branches below depend on pass vs fail or local vs CI.
          # Exclude `data_warehouse.yaml` from the diff since it's generated by the warehouse extension,
          # which isn't loaded in this test suite. We filter the diff output since `git diff --no-index`
          # doesn't support pathspec exclusions.
          diff = `git diff --no-index #{File.join(config_dir, "schema", "artifacts")} config/schema/artifacts #{"--color" if $stdout.tty?}`
          # Strip ANSI color codes so the regex can match when --color is enabled.
          diff_without_colors = diff.gsub(/\e\[\d*m/, "")
          filtered_diff = diff_without_colors.gsub(/^diff --git.*?data_warehouse\.yaml.*?(?=^diff --git|\z)/m, "")

          unless filtered_diff == ""
            RSpec.world.reporter.message("\n\nThe schema artifact diff:\n\n#{filtered_diff}")

            fail <<~EOS
              Expected no formatting changes to the test/development schema artifacts, but there are some. If this is by design,
              please delete and re-dump the artifacts with differences to bring our local artifacts up to date with the current
              formatting. See "The schema artifact diff:" above for details.
            EOS
          end
          # :nocov:
        end

        it "retains `extend schema` in the dumped SDL if ElasticGraph includes it in the generated SDL string" do
          write_elastic_graph_schema_def_code(extra_sdl: "")
          run_rake("schema_artifacts:dump")

          # `extend` should not be added by default...
          expect(read_artifact(GRAPHQL_SCHEMA_FILE)).not_to include("extend")

          write_elastic_graph_schema_def_code(extra_sdl: <<~EOS)
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

        it "successfully checks schema artifacts when the rake task is run within a minimal schema definition bundle" do
          # We want to ensure that `elasticgraph-schema_definition` gem declares (in its gemspec) all the
          # dependencies necessary for the schema definition rake tasks. Unfortunately, its test suite
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
            gem "elasticgraph-json_ingestion", path: "#{CommonSpecHelpers::REPO_ROOT}/elasticgraph-json_ingestion"

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

            require "elastic_graph/json_ingestion/schema_definition/api_extension"
            require "elastic_graph/schema_definition/rake_tasks"

            ElasticGraph::SchemaDefinition::RakeTasks.new(
              schema_element_name_form: :snake_case,
              index_document_sizes: true,
              path_to_schema: "\#{project_root}/config/schema.rb",
              schema_artifacts_directory: "\#{project_root}/config/schema/artifacts",
              extension_modules: [ElasticGraph::JSONIngestion::SchemaDefinition::APIExtension]
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

        def write_elastic_graph_schema_def_code(component_suffix: "", extra_sdl: "", component_extras: "", number_of_shards: 5)
          code = <<~EOS
            Thread.current[:eg_schema_load_count] = (Thread.current[:eg_schema_load_count] || 0) + 1
            if Thread.current[:eg_schema_load_count] > 1
              raise "Schema file \#{__FILE__} was loaded \#{Thread.current[:eg_schema_load_count]} times in a single run!"
            end

            ElasticGraph.define_schema do |schema|
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
                t.field "name", "String!"
                t.field "designer_id", "ID"
                t.index "components#{component_suffix}", number_of_shards: #{number_of_shards}

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
            Thread.current[:eg_schema_load_count] = (Thread.current[:eg_schema_load_count] || 0) + 1
            if Thread.current[:eg_schema_load_count] > 1
              raise "Schema file \#{__FILE__} was loaded \#{Thread.current[:eg_schema_load_count]} times in a single run!"
            end

            ElasticGraph.define_schema do |schema|
              schema.object_type "MyType" do |t|
                t.field "id", "ID!"
                #{'t.field "timestamp", "DateTime"' if include_date_time_fields}
                #{'t.field "timestamps", "[DateTime]"' if include_date_time_fields}
                t.index "my_type"
              end
            end
          EOS

          run_rake("schema_artifacts:dump")
          ::YAML.safe_load(read_artifact(RUNTIME_METADATA_FILE))
        end

        def expect_up_to_date_artifacts
          output = nil

          expect {
            output = run_rake("schema_artifacts:check")
          }.not_to raise_error

          expect(output).to include(DATASTORE_CONFIG_FILE, RUNTIME_METADATA_FILE, "up to date")
        end

        def expect_all_artifacts_out_of_date_because_they_havent_been_dumped
          expect {
            run_rake("schema_artifacts:check")
          }.to abort_with { |error|
            expect(error.message).to eq(<<~EOS.strip)
              3 schema artifact(s) are out of date. Run `bundle exec rake schema_artifacts:dump` to update the following artifact(s):

              1. config/schema/artifacts/datastore_config.yaml (file does not exist)
              2. config/schema/artifacts/runtime_metadata.yaml (file does not exist)
              3. config/schema/artifacts/schema.graphql (file does not exist)
            EOS
          }
        end

        def expect_out_of_date_artifacts_with_details(example_diff, test_color: false)
          expect {
            run_rake("schema_artifacts:check", pretend_tty: test_color)
          }.to abort_with { |error|
            expect(error.message.lines.first(5).join).to eq(<<~EOS)
              3 schema artifact(s) are out of date. Run `bundle exec rake schema_artifacts:dump` to update the following artifact(s):

              1. config/schema/artifacts/datastore_config.yaml (see [1] below for the first 50 lines of the diff)
              2. config/schema/artifacts/runtime_metadata.yaml (see [2] below for the first 50 lines of the diff)
              3. config/schema/artifacts/schema.graphql (see [3] below for the first 50 lines of the diff)
            EOS

            expect(error.message).to include(example_diff)
          }
        end

        def read_artifact(name)
          path = File.join("config", "schema", "artifacts", name)
          File.exist?(path) && File.read(path)
        end
      end

      def run_rake(
        *args,
        pretend_tty: false,
        path_to_schema: "schema.rb",
        include_extension_module: true,
        extension_modules: [],
        derived_type_name_formats: {},
        type_name_overrides: {},
        enum_value_overrides_by_type: {}
      )
        Thread.current[:eg_schema_load_count] = nil

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
            extension_modules: extension_modules + [extension_module].compact,
            derived_type_name_formats: derived_type_name_formats,
            type_name_overrides: type_name_overrides,
            enum_value_overrides_by_type: enum_value_overrides_by_type,
            output: output
          )
        end
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
