# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/graphql"
require "elastic_graph/indexer"
require "elastic_graph/indexer/test_support/converters"
require "elastic_graph/indexer/spec_support/event_matcher"
require "factory_bot"

RSpec.shared_examples "an ElasticGraph project" do |repo_root: Dir.pwd,
  settings_dir: "config/settings",
  use_settings_yaml: "local.yaml",
  ignored_factories: [],
  factory_iterations: 100|

  settings_yaml_file_to_use = ::File.join(settings_dir, use_settings_yaml)

  # Our settings files reference some files relative to the repo root, but we want to support
  # running this spec file from both the repo root and from each gem dir. To avoid problems,
  # here we force the examples (and all hooks, including :context hooks) to run with the current
  # directory set to the repo root.
  before(:context) do |ex|
    @original_current_dir = ::Dir.pwd
    ::Dir.chdir(repo_root)
  end

  after(:context) do
    ::Dir.chdir(@original_current_dir)
  end

  if settings_dir
    describe "a fully configured lambda settings file" do
      settings_files = Dir[File.join(repo_root, settings_dir, "*.{yml,yaml}")]

      specify "this test file is looking for settings files in the right place" do
        expect(settings_files).not_to be_empty
      end

      settings_files.each do |file_name|
        describe "the `#{file_name}` settings file" do
          it "can boot each part of ElasticGraph and has `number_of_shards` configured on every index definition" do
            all_components = [::ElasticGraph::Admin, ::ElasticGraph::GraphQL, ::ElasticGraph::Indexer].map do |klass|
              klass.from_yaml_file(file_name)
            end

            graphql = all_components.grep(::ElasticGraph::GraphQL).first

            all_components.each do |comp|
              # this will raise an error if any indices are not configured.
              comp.datastore_core.index_definitions_by_name

              # Verify that every index definition has an explicit `number_of_shards` configured. It's easy to forget
              # and can't be changed once the index is created so we want to force it to be chosen. The default of `1`
              # is probably never appropriate.
              index_def_names_without_number_of_shards =
                comp.datastore_core.index_definitions_by_name.values.filter_map do |index_def|
                  # :nocov: -- currently not executed during this gem's own test suite run
                  index_def.name unless index_def.env_index_config.setting_overrides.key?("number_of_shards")
                  # :nocov:
                end
              expect(index_def_names_without_number_of_shards).to be_empty,
                "Expected all index definitions to configure the `number_of_shards` in #{file_name}, but the following did not:\n" \
                "  - #{index_def_names_without_number_of_shards.join("\n  - ")}"
            end

            # This will raise an error if health check settings are invalid.
            graphql.graphql_http_endpoint
          end
        end
      end
    end
  end

  ignored_factories_set = ignored_factories.to_set
  typenames_by_factory_name = ::FactoryBot.factories.filter_map do |factory|
    typename_attr = factory.send(:attributes).find { |a| a.name == :__typename }
    next if typename_attr.nil? || ignored_factories_set.include?(factory.name)

    begin
      [factory.name, typename_attr.to_proc.call]
    rescue StandardError, NotImplementedError
      # Don't consider factories that raise an error from `__typename`.
    end
  end.to_h

  indexer, all_type_names, event_types = Dir.chdir(repo_root) do
    indexer = ::ElasticGraph::Indexer.from_yaml_file(settings_yaml_file_to_use)
    all_defs = indexer.schema_artifacts
      .json_schemas_for(indexer.schema_artifacts.latest_json_schema_version)
      .fetch("$defs")

    event_types = all_defs
      .fetch("ElasticGraphEventEnvelope")
      .fetch("properties")
      .fetch("type")
      .fetch("enum")
      .to_set

    [indexer, all_defs.keys.to_set, event_types]
  end

  describe "Factories" do
    specify "all factories have valid `__typename` values" do
      unknown_type_names_by_factory_name = typenames_by_factory_name.reject { |k, v| all_type_names.include?(v) }

      expect(unknown_type_names_by_factory_name).to be_empty,
        "Expected all factory `__typename` values to be valid, but the following did not match any defined indexed types: #{unknown_type_names_by_factory_name.values.sort}. " \
        "If any `__typename` values are invalid, fix them; otherwise, pass `ignored_factories: #{unknown_type_names_by_factory_name.keys.sort.inspect}` to ignore them " \
        "or make sure that they are defined as indexed types (by defining `t.index_name \"...\"` on them)."
    end

    typenames_by_factory_name.each do |factory_name, typename|
      next unless event_types.include?(typename)

      describe "the :#{factory_name} factory" do
        # We use `aggregate_failures: false` so that we stop on the first failure. Getting all of them can be overwhelming.
        it "builds a record that passes ElasticGraph validation", aggregate_failures: false do
          # The factory generates random data. To give us confidence that it doesn't generate
          # good data usually and bad data rarely, we generate 100 events and verify that they
          # are all valid.
          factory_iterations.times do
            record = ::FactoryBot.build(factory_name)
            event = ::ElasticGraph::Indexer::TestSupport::Converters.upsert_events_for_records([record]).first

            expect(event).to be_a_valid_elastic_graph_event(for_indexer: indexer) { |v| v.with_unknown_properties_disallowed }

            # Also try building a datastore bulk operation for each event. Occasionally we've seen bugs in
            # elasticgraph-indexer that only manifest in specific schema situations that our main ElasticGraph
            # test suite may not cover, so this'll surface whether elasticgraph-indexer produces exceptions from
            # the Ruby code while processing events for the current schema.
            #
            # Note: we could attempt to _actually_ index it into the datastore here (which would provide even
            # greater confidence), but we don't expect the datastore to be booted and available when these tests
            # are running, and we don't want to have to manage cleaning up datastore state as part of these
            # tests. Still, it's a potential further step we could take with this in the future.
            indexer.operation_factory.build(event).operations.each(&:to_datastore_bulk)
          end
        end
      end
    end
  end
end
