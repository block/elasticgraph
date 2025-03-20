# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "delegate"
require "elastic_graph/apollo/schema_definition/api_extension"
require "elastic_graph/local/rake_tasks"
require "elastic_graph/schema_definition/rake_tasks"
require "yaml"

project_root = File.expand_path(__dir__)

# Load tasks from config/site/Rakefile
load "#{project_root}/config/site/Rakefile"

test_port = "#{project_root}/config/settings/test.yaml.template"
  .then { |f| ::YAML.safe_load_file(f, aliases: true).fetch("datastore").fetch("clusters").fetch("main").fetch("url") }
  .then { |url| Integer(url[/localhost:(\d+)$/, 1]) }

schema_def_output = ::SimpleDelegator.new($stdout)
def schema_def_output.puts(*objects)
  # There's an edge case (involving a definition of a `count` field competing with a `count` field that ElasticGraph
  # wants to define) that ElasticGraph warns about, and our schema definition intentionally exercises that place. We
  # don't want to see the warning in our output here since it's by design, so here we silence it.
  return if /WARNING: Since a `\w+\.count` field exists/.match?(objects.first.to_s)

  super
end

module TrackLastNewInstance
  attr_reader :last_new_instance

  def new(...)
    super.tap do |instance|
      @last_new_instance = instance
    end
  end

  ElasticGraph::SchemaDefinition::RakeTasks.extend self
end

configure_local_rake_tasks = ->(tasks) do
  tasks.schema_element_name_form = :snake_case
  tasks.enforce_json_schema_version = false
  tasks.index_document_sizes = true
  tasks.env_port_mapping = {test: test_port}
  tasks.output = schema_def_output

  tasks.define_fake_data_batch_for(:widgets) do
    require "rspec/core" # the factories file expects RSpec to be loaded, so load it.

    # spec_support is not a full-fledged gem and is not on the load path, so we have to
    # add it's lib dir to the load path before we can require things from it.
    $LOAD_PATH.unshift ::File.join(__dir__, "spec_support", "lib")
    require "elastic_graph/spec_support/factories"

    batch = []
    batch.concat(manufacturers = Array.new(10) { FactoryBot.build(:manufacturer) })
    batch.concat(electrical_parts = Array.new(10) { FactoryBot.build(:electrical_part, manufacturer: manufacturers.sample) })
    batch.concat(mechanical_parts = Array.new(10) { FactoryBot.build(:mechanical_part, manufacturer: manufacturers.sample) })
    batch.concat(components = Array.new(10) { FactoryBot.build(:component, parts: (electrical_parts + mechanical_parts).sample(rand(5))) })

    components = components.shuffle

    batch.concat(Array.new(10) { FactoryBot.build(:address, manufacturer: manufacturers.sample) })
    batch.concat(Array.new(10) do
      # Since we now use `sourced_from` to copy `Widget` fields onto `Component` documents, we need to make
      # sure that we don't have conflicting widget <-> component relationships defined. Each component can
      # have at most 1 widget, so we use `components.shift` here to ensure that a component isn't re-assigned.
      widget_components = Array.new(rand(3)) { components.shift }.compact
      FactoryBot.build(:widget, components: widget_components)
    end)

    batch.concat(sponsors = Array.new(10) { FactoryBot.build(:sponsor) })
    batch.concat(Array.new(10) { FactoryBot.build(:team, sponsors: sponsors.sample(rand(3))) })
    batch
  end

  tested_datastore_versions = ::YAML.load_file(::File.expand_path("config/tested_datastore_versions.yaml", __dir__))
  tasks.elasticsearch_versions = tested_datastore_versions.fetch("elasticsearch")
  tasks.opensearch_versions = tested_datastore_versions.fetch("opensearch")
end

ElasticGraph::Local::RakeTasks.new(
  local_config_yaml: "config/settings/development.yaml",
  path_to_schema: "config/schema.rb",
  &configure_local_rake_tasks
)

schema_def_rake_tasks = ElasticGraph::SchemaDefinition::RakeTasks.last_new_instance

namespace :apollo do
  ElasticGraph::Local::RakeTasks.new(
    local_config_yaml: "config/settings/development_with_apollo.yaml",
    path_to_schema: "config/schema.rb"
  ) do |tasks|
    configure_local_rake_tasks.call(tasks)
    tasks.schema_definition_extension_modules = [ElasticGraph::Apollo::SchemaDefinition::APIExtension]
  end
end

# When we update our `update_index_data.painless` script, the process can be pretty annoying.
# After updating the script, you have to:
#
# 1. Run `rake schema_artifacts:dump` to generate the `datastore_scripts.yaml` with the new script and to get the script's new id.
# 2. Copy that new id and set `INDEX_DATA_UPDATE_SCRIPT_ID` to it in `constants.rb`.
# 3. Run `rake schema_artifacts:dump` a second time so that `runtime_metadata.yaml`--which depends on the constant--generates correctly.
#
# Here we hook into the `schema_artifacts:dump` task and automate this process. Each time we dump the artifacts,
# this will do a "pre-flight" of the generation of the datastore scripts so that we can get the new constant value.
# We then update it in `constants.rb` as needed, and then allow `schema_artifacts:dump` to proceed, so that it runs
# with the new constant value.
# standard:disable Rake/Desc --  we are just hooking into an existing task here, not defining a new one.
task "schema_artifacts:check" => "apollo:schema_artifacts:check"
task "schema_artifacts:dump" => [:update_artifact_derived_constants, "apollo:schema_artifacts:dump"]
task :update_artifact_derived_constants do
  script_id_pattern = "update_index_data_[0-9a-f]+"

  update_index_data_script_id = schema_def_rake_tasks
    .send(:schema_definition_results)
    .datastore_scripts.keys
    .grep(/\A#{script_id_pattern}\z/)
    .first

  constants_path = ::File.join(project_root, "elasticgraph-support/lib/elastic_graph/constants.rb")
  constants_contents = ::File.read(constants_path)

  if (old_line_match = /^ *INDEX_DATA_UPDATE_SCRIPT_ID = "(#{script_id_pattern})"$/.match(constants_contents))
    old_script_id = old_line_match.captures.first
    if update_index_data_script_id == old_script_id
      puts "`INDEX_DATA_UPDATE_SCRIPT_ID` in `constants.rb` is already set correctly; leaving unchanged."
    else
      constants_contents = constants_contents.gsub(old_script_id, update_index_data_script_id)
      ::File.write(constants_path, constants_contents)
      # Set the constant to the new value so that it takes effect for `schema_artifacts:dump` when that resumes after this.
      ElasticGraph.const_set(:INDEX_DATA_UPDATE_SCRIPT_ID, update_index_data_script_id)
      puts "Updated `INDEX_DATA_UPDATE_SCRIPT_ID` in `constants.rb` from #{old_script_id} to #{update_index_data_script_id}."
    end
  else
    puts "Warning: could not locate the `INDEX_DATA_UPDATE_SCRIPT_ID =` in `constants.rb` to update."
  end
end
# standard:enable Rake/Desc

# Here we hook into the `[datastore]:test:boot` tasks and do one extra bit of preparation for our tests.
# Each time we boot the datastore, we want to delete the directory that our `ClusterConfigurationManager`
# stores state files in. The state files are used by it to avoid having to reconfigure the datastore when
# the configuration hasn't changed and the datastore hasn't been restarted. That makes the setup for our
# test suite much faster. However, it's essential that we clear out these files every time we boot the datastore
# for our tests or else the `ClusterConfigurationManager` could mistakenly leave the datastore unconfigured
# after we've rebooted it.
# standard:disable Rake/Desc -- these tasks aren't meant to be individually callable; we're just hooking into other tasks here.
task :boot_prep_for_tests do
  require "fileutils"
  require "rspec/core"

  original_env = ENV.to_h

  begin
    ENV.delete("COVERAGE") # so SimpleCov doesn't get loaded when we load `spec_helper` below.
    $LOAD_PATH.unshift ::File.join(project_root, "spec_support/lib")
    require_relative "spec_support/spec_helper"
    require "elastic_graph/spec_support/cluster_configuration_manager"
  ensure
    ENV.replace(original_env)
  end

  state_file_dir = ::File.join(project_root, ElasticGraph::ClusterConfigurationManager::STATE_FILE_DIR)
  ::FileUtils.rm_rf(state_file_dir)
end

::YAML.load_file("#{project_root}/config/tested_datastore_versions.yaml").each do |variant, versions|
  namespace variant do
    namespace :test do
      %i[boot daemon].each { |command| task command => :boot_prep_for_tests }
      versions.each do |version|
        namespace version do
          %i[boot daemon].each { |command| task command => :boot_prep_for_tests }
        end
      end
    end
  end
end
# standard:enable Rake/Desc
