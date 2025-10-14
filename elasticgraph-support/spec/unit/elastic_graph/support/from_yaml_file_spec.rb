# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/from_yaml_file"
require "json"
require "rake/tasklib"

module ElasticGraph
  module Support
    RSpec.describe FromYamlFile, :in_temp_dir do
      before do
        stub_const "ExampleComponent", component_class
      end

      let(:component_class) do
        ::Data.define(:sub_settings_by_name, :datastore_client_customization_block) do
          extend FromYamlFile

          def self.from_parsed_yaml(parsed_yaml, &datastore_client_customization_block)
            new(
              sub_settings_by_name: parsed_yaml.fetch("sub_settings_by_name"),
              datastore_client_customization_block: datastore_client_customization_block
            )
          end
        end
      end

      context "when extended onto a class that implements `.from_parsed_yaml`" do
        it "builds the class using `.from_parsed_yaml` after first loading YAML the file from disk with alias support" do
          ::File.write("settings.yaml", <<~EOS)
            sub_settings_by_name:
              foo: &foo_settings
                size: 12
              bar: *foo_settings
          EOS

          customization_block = lambda { |block| }
          instance = component_class.from_yaml_file("settings.yaml", datastore_client_customization_block: customization_block)

          expect(instance).to be_a(component_class)
          expect(instance.sub_settings_by_name).to eq("foo" => {"size" => 12}, "bar" => {"size" => 12})
          expect(instance.datastore_client_customization_block).to be(customization_block)
        end

        it "allows the settings to be overridden using the provided block before the object is built" do
          ::File.write("settings.yaml", <<~EOS)
            sub_settings_by_name:
              foo: &foo_settings
                size: 12
              bar: *foo_settings
          EOS

          instance = component_class.from_yaml_file("settings.yaml") do |settings|
            settings.merge("sub_settings_by_name" => settings.fetch("sub_settings_by_name").merge(
              "bar" => {"size" => 14}
            ))
          end

          expect(instance).to be_a(component_class)
          expect(instance.sub_settings_by_name).to eq(
            "foo" => {"size" => 12},
            "bar" => {"size" => 14}
          )
        end
      end

      describe FromYamlFile::ForRakeTasks, :rake_task do
        let(:rake_tasks_class) do
          component = component_class

          Class.new(::Rake::TaskLib) do
            extend FromYamlFile::ForRakeTasks.new(component)

            def initialize(output:, &load_component)
              desc "Uses the component"
              task :use_component do
                component = load_component.call
                output.puts "Subsettings: #{::JSON.pretty_generate(component.sub_settings_by_name)}"
              end
            end
          end
        end

        it "loads the component from the named yaml file and provides it to the rake task library" do
          ::File.write("settings.yaml", <<~EOS)
            sub_settings_by_name:
              foo:
                size: 12
          EOS

          output = run_rake "use_component"

          expect(output).to eq(<<~EOS)
            Subsettings: {
              "foo": {
                "size": 12
              }
            }
          EOS
        end

        it "tells the user to regenerate schema artifacts if the component fails to load" do
          expect {
            run_rake "use_component"
          }.to raise_error(a_string_including(
            "Failed to load `ExampleComponent` with `settings.yaml`. This can happen if the schema artifacts are out of date.",
            "Run `bundle exec rake schema_artifacts:dump` and try again.",
            "No such file or directory"
          ))
        end

        it "loads the artifacts lazily, allowing tasks to be listed when the artifacts do not exist or are out of date" do
          output = run_rake "--tasks"

          expect(output).to eq(<<~EOS)
            rake use_component  # Uses the component
          EOS
        end

        def run_rake(task)
          super(task) do |output|
            rake_tasks_class.from_yaml_file("settings.yaml", output: output)
          end
        end
      end
    end
  end
end
