# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/apollo/schema_definition/api_extension"
require "elastic_graph/schema_artifacts/runtime_metadata/schema_element_names"
require "elastic_graph/schema_definition/api"
require "elastic_graph/schema_definition/schema_artifact_manager"
require "rspec/mocks"
require "tmpdir"

module ElasticGraph
  project_root = ::File.expand_path("../../..", __dir__)

  ::YARD::Doctest.configure do |doctest|
    # Run each doctest in an empty temp dir. This ensures that the doc tests are not able
    # to implicitly rely on the surrounding file system state, and allows doc test to interactive
    # with the file system as needed without worrying about it corrupting our local file system.
    doctest.before do
      ::RSpec::Mocks.setup
      @original_pwd = ::Dir.pwd
      @tmp_dir = ::Dir.mktmpdir
      @original_load_path = $LOAD_PATH.dup
      ::Dir.chdir(@tmp_dir)
    end

    doctest.after do
      ::RSpec::Mocks.teardown
      $LOAD_PATH.replace(@original_load_path)
      ::Dir.chdir(@original_pwd)
      ::FileUtils.rm_rf(@tmp_dir)
    end

    # Many doc tests are for the schema definition API, and need to be run with a schema definition
    # API instance being active.
    descriptions_needing_schema_def_api_and_extension_modules = {
      "ElasticGraph.define_schema" => [],
      "ElasticGraph::Apollo::SchemaDefinition" => [ElasticGraph::Apollo::SchemaDefinition::APIExtension],
      "ElasticGraph::SchemaDefinition" => []
    }

    descriptions_needing_schema_def_api_and_extension_modules.each do |description, extension_modules|
      doctest.before(description) do
        @api = SchemaDefinition::API.new(
          SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: :camelCase, overrides: {}),
          true,
          extension_modules: extension_modules
        )

        # This is required in all schemas, but we don't want to have to put in all our examples,
        # so we set it here.
        @api.json_schema_version 1

        @api.object_type "SomeIndexedTypeToEnsureQueryTypeHasFields" do |t|
          t.field "id", "ID"
          t.index "some_indexed_type"
        end

        # Store the api instance so that `ElasticGraph.define_schema` can access it.
        ::Thread.current[:ElasticGraph_SchemaDefinition_API_instance] = @api
      end

      doctest.after(description) do
        ::Thread.current[:ElasticGraph_SchemaDefinition_API_instance] = nil

        artifacts_manager = SchemaDefinition::SchemaArtifactManager.new(
          schema_definition_results: @api.results,
          schema_artifacts_directory: "#{@tmp_dir}/schema_artifacts",
          enforce_json_schema_version: true,
          output: ::StringIO.new
        )

        # Dump the artifacts to surface any issues with the schema definition.
        artifacts_manager.dump_artifacts
      end
    end

    doctest.before "ElasticGraph::SchemaDefinition::API#json_schema_version" do
      ElasticGraph.define_schema do |schema|
        # `schema.json_schema_version` raises an error when the version is set more than once.
        # By default we set it above. Here we clear it to allow our example to set it.
        schema.state.json_schema_version = nil
      end
    end

    doctest.before "ElasticGraph::SchemaDefinition::SchemaElements::ScalarType#coerce_with" do
      ::FileUtils.mkdir_p "coercion_adapters"
      ::File.write("coercion_adapters/phone_number.rb", <<~EOS)
        module CoercionAdapters
          class PhoneNumber
            def self.coerce_input(value, ctx)
            end

            def self.coerce_result(value, ctx)
            end
          end
        end
      EOS
    end

    doctest.before "ElasticGraph::SchemaDefinition::SchemaElements::ScalarType#prepare_for_indexing_with" do
      ::FileUtils.mkdir_p "indexing_preparers"
      ::File.write("indexing_preparers/phone_number.rb", <<~EOS)
        module IndexingPreparers
          class PhoneNumber
            def self.prepare_for_indexing(value)
            end
          end
        end
      EOS
    end

    doctest.before "ElasticGraph::SchemaDefinition::API#register_graphql_resolver@Register a custom resolver for use by a custom `Query` field" do
      # The validation performed on the resolver attempts to read the `source_location` of methods of the resolver, but
      # in this context, `eval` is being used and the file doesn't exist! So we have to stub it out here.
      extend ::RSpec::Mocks::ExampleMethods
      allow(::File).to receive(:read).and_wrap_original do |original, file_name|
        if file_name.include?("(eval at")
          ([file_name] * 10).join("\n")
        else
          original.call(file_name)
        end
      end

      $LOAD_PATH << ::Dir.pwd
      ::File.write("add_resolver.rb", "")
    end

    doctest.before "ElasticGraph::SchemaDefinition::API#register_graphql_resolver@Register a custom resolver that uses lookahead" do
      $LOAD_PATH << ::Dir.pwd
      ::File.write("artist_resolver.rb", "")
    end

    [
      "ElasticGraph::Apollo@Use elasticgraph-apollo in a project",
      "ElasticGraph::Apollo::SchemaDefinition::APIExtension@Define local rake tasks with this extension module",
      "ElasticGraph::Local::RakeTasks"
    ].each do |description|
      doctest.before description do
        ::FileUtils.mkdir_p "config/settings"
        ::FileUtils.cp "#{project_root}/config/settings/development.yaml", "config/settings/local.yaml"
      end
    end

    [
      "ElasticGraph::Rack::GraphiQL",
      "ElasticGraph::Rack::GraphQLEndpoint"
    ].each do |description|
      doctest.before description do
        require "elasticsearch"
        ::FileUtils.ln_s "#{project_root}/config", "config"

        # These examples are the contents of a config.ru file which is evaluated in the context of a Rack::Builder
        # instance. We need to define `run` to be compatible with the normal config.ru context.
        def self.run(app)
        end
      end
    end
  end

  # Here we work around a bug in yard-doctest. Usually it evaluates examples in the context of the `YARD::Doctest::Example` instance.
  # However, when the constant named by the example is defined, it instead evaluates the example in the context of the class itself.
  #
  # This creates ordering dependency bugs for us--specifically:
  #
  # * The example for `ElasticGraph::Rack::GraphiQL` and `ElasticGraph::Rack::GraphQLEndpoint` both depend on `run` being
  #   defined since they are `config.ru` examples.
  # * We have a `before` hook above which defines the `run` method they need.
  # * When `ElasticGraph::Rack::GraphiQL` is loaded it turns around and loads `ElasticGraph::Rack:::GraphQLEndpoint` since
  #   it depends on it.
  # * That means that if the `GraphQLEndpoint` runs first everything works fine; but if the `GraphiQL` examples runs first, then
  #   when the `GraphQLEndpoint` example runs, its class is defined and it changes how yard-doctest evaluates the example.
  #
  # To ensure consistent, predictable evaluation, we override `evaluate` to _always_ use the binding of the example instance,
  # avoiding this problem.
  module YARDDoctestExampleBugFix
    def evaluate(code, bind)
      super(code, nil)
    end

    ::YARD::Doctest::Example.prepend self
  end
end
