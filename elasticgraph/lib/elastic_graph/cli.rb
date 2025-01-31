# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "bundler"
require "elastic_graph/version"
require "fileutils"
require "shellwords"
require "thor"

module ElasticGraph
  class CLI < ::Thor
    include ::Thor::Actions

    # Tell Thor where our template files live
    def self.source_root
      ::File.expand_path("project_template", __dir__)
    end

    def self.exit_on_failure?
      true
    end

    VALID_DATASTORES = %w[elasticsearch opensearch]

    option :datastore, desc: "elasticsearch or opensearch", type: :string, default: "opensearch"
    desc "new APP_NAME", "Generate a new ElasticGraph project in APP_NAME."
    def new(app_path)
      new_app_path = ::File.join(::Dir.pwd, app_path)
      app_name = ::File.basename(new_app_path)

      unless app_name.match?(/\A[a-z_]+\z/)
        raise ::Thor::Error, "App name must be in `snake_case` form but was not: `#{app_name}`."
      end

      unless VALID_DATASTORES.include?(options[:datastore])
        raise ::Thor::Error, "Invalid datastore option: #{options[:datastore]}. Must be #{VALID_DATASTORES.join(" or ")}."
      end

      say "Creating a new ElasticGraph app called '#{app_name}' at: #{new_app_path}", :green

      setup_env = SetupEnv.new(
        app_name: app_name,
        app_module: app_name.split("_").map(&:capitalize).join,
        datastore: options.fetch(:datastore)
      )

      ElasticGraph.with_setup_env(setup_env) do
        # Recursively copy all files from project_template into the new_app_path
        directory ".", new_app_path, exclude_pattern: %r{/lib/app_name/}
        directory "lib/app_name", ::File.join(new_app_path, "lib", app_name)
      end

      inside new_app_path do
        ::Bundler.with_unbundled_env do
          run "bundle install"
          run "bundle exec rake schema_artifacts:dump query_registry:dump_variables:all build"
        end

        run "git init"
        run "git add ."
        run "git commit -m 'Bootstrapped ElasticGraph with `elasticgraph new`.'"
      end

      say "Successfully bootstrapped '#{app_name}' as a new ElasticGraph project.", :green

      say <<~INSTRUCTIONS, :yellow
        Next steps:
          1. cd #{app_path}
          2. Run `bundle exec rake boot_locally` to try it out in your browser.
          3. Run `bundle exec rake -T` to view other available tasks.
          4. Customize your new project as needed.
      INSTRUCTIONS
    end
  end

  class SetupEnv < ::Data.define(:app_name, :app_module, :datastore)
    DATASTORE_NAMES = {"elasticsearch" => "Elasticsearch", "opensearch" => "OpenSearch"}
    DATASTORE_UI_NAMES = {"elasticsearch" => "Kibana", "opensearch" => "OpenSearch Dashboards"}
    OTHER_DATASTORE = {"elasticsearch" => "opensearch", "opensearch" => "elasticsearch"}

    def datastore_name
      DATASTORE_NAMES.fetch(datastore)
    end

    def datastore_ui_name
      DATASTORE_UI_NAMES.fetch(datastore)
    end

    def other_datastore
      OTHER_DATASTORE.fetch(datastore)
    end

    def other_datastore_name
      DATASTORE_NAMES.fetch(other_datastore)
    end

    def ruby_major_minor
      "3.4"
    end
  end

  singleton_class.attr_reader :setup_env

  def self.with_setup_env(setup_env)
    original_setup_env = self.setup_env
    @setup_env = setup_env
    yield
  ensure
    @setup_env = original_setup_env
  end
end
