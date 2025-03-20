# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/local/rake_tasks"
require "elastic_graph/schema_definition/rake_tasks"
require "pathname"
require "tmpdir"

module ElasticGraph
  module Local
    RSpec.describe RakeTasks, :rake_task do
      let(:config_dir) { ::Pathname.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config")) }

      it "generates a complete set of tasks when no block is provided" do
        output = run_rake "-T" do
          RakeTasks.new(
            local_config_yaml: config_dir / "settings" / "development.yaml",
            path_to_schema: config_dir / "schema.rb"
          )
        end

        expected_snippet_1 = <<~EOS
          rake boot_graphiql[port,rackup_args,no_open]    # Boots ElasticGraph locally with the GraphiQL UI, and opens it in a browser
          rake boot_locally[port,rackup_args,no_open]     # Boots ElasticGraph locally from scratch: boots Elasticsearch, configures it, indexes fake data, and boots GraphiQL
          rake clusters:configure:dry_run                 # Dry-runs the configuration of datastore clusters, including indices, settings, and scripts / (after first dumping the schema artifacts)
          rake clusters:configure:perform                 # Performs the configuration of datastore clusters, including indices, settings, and scripts / (after first dumping the schema artifacts)
        EOS

        expected_snippet_2 = <<~EOS
          rake indices:drop[index_def_name,cluster_name]  # Drops the specified index definition on the specified datastore cluster
          rake indices:drop_prototypes                    # Drops all prototype index definitions on all datastore clusters
        EOS

        expected_snippet_3 = <<~EOS
          rake schema_artifacts:check                     # Checks the artifacts to make sure they are up-to-date, raising an exception if not
          rake schema_artifacts:dump                      # Dumps all schema artifacts based on the current ElasticGraph schema definition
        EOS

        expect(output).to include(expected_snippet_1, expected_snippet_2, expected_snippet_3)
      end

      context "when the local config file configures an `elasticsearch` backend" do
        it "defines elasticsearch tasks" do
          output = run_rake_with_yaml_changes "-T" do |config|
            config["datastore"]["clusters"].values.each do |cluster|
              cluster["backend"] = "elasticsearch"
            end

            config
          end

          # Note: we are careful to avoid asserting on exact versions here, since we don't specify any in this test and
          # we want to be able to update `tested_datastore_versions.yaml` without breaking this test.
          expect(output).to include(*%w[
            rake elasticsearch:local:boot
            rake elasticsearch:local:daemon
            rake elasticsearch:local:halt
          ])

          expect(output).to exclude("opensearch")
        end
      end

      context "when the local config file configures an `opensearch` backend" do
        it "defines opensearch tasks" do
          output = run_rake_with_yaml_changes "-T" do |config|
            config["datastore"]["clusters"].values.each do |cluster|
              cluster["backend"] = "opensearch"
            end

            config
          end

          # Note: we are careful to avoid asserting on exact versions here, since we don't specify any in this test and
          # we want to be able to update `tested_datastore_versions.yaml` without breaking this test.
          expect(output).to include(*%w[
            rake opensearch:local:boot
            rake opensearch:local:daemon
            rake opensearch:local:halt
          ])

          expect(output).to exclude("elasticsearch")
        end
      end

      it "defines a task which indexes locally" do
        output = run_rake_with_overrides "-T", "index_fake_data:" do |t|
          t.define_fake_data_batch_for(:widgets) {}
        end

        expect(output).to eq(<<~EOS)
          rake index_fake_data:widgets[num_batches]  # Indexes num_batches of widgets fake data into the local datastore
        EOS
      end

      describe "elasticsearch/opensearch tasks" do
        it "generates a rake task for each combination of environment and elasticsearch/opensearch version" do
          output = list_datastore_management_tasks

          expect(output).to eq(<<~EOS)
            rake elasticsearch:example:8.7.1:boot    # Boots Elasticsearch 8.7.1 for the example environment on port 9612 (and Kibana on port 19612)
            rake elasticsearch:example:8.7.1:daemon  # Boots Elasticsearch 8.7.1 as a background daemon for the example environment on port 9612 (and Kibana on port 19612)
            rake elasticsearch:example:8.7.1:halt    # Halts the Elasticsearch 8.7.1 daemon for the example environment
            rake elasticsearch:example:8.8.1:boot    # Boots Elasticsearch 8.8.1 for the example environment on port 9612 (and Kibana on port 19612)
            rake elasticsearch:example:8.8.1:daemon  # Boots Elasticsearch 8.8.1 as a background daemon for the example environment on port 9612 (and Kibana on port 19612)
            rake elasticsearch:example:8.8.1:halt    # Halts the Elasticsearch 8.8.1 daemon for the example environment
            rake elasticsearch:example:boot          # Boots Elasticsearch 8.8.1 for the example environment on port 9612 (and Kibana on port 19612)
            rake elasticsearch:example:daemon        # Boots Elasticsearch 8.8.1 as a background daemon for the example environment on port 9612 (and Kibana on port 19612)
            rake elasticsearch:example:halt          # Halts the Elasticsearch 8.8.1 daemon for the example environment
            rake elasticsearch:local:8.7.1:boot      # Boots Elasticsearch 8.7.1 for the local environment on port 9334 (and Kibana on port 19334)
            rake elasticsearch:local:8.7.1:daemon    # Boots Elasticsearch 8.7.1 as a background daemon for the local environment on port 9334 (and Kibana on port 19334)
            rake elasticsearch:local:8.7.1:halt      # Halts the Elasticsearch 8.7.1 daemon for the local environment
            rake elasticsearch:local:8.8.1:boot      # Boots Elasticsearch 8.8.1 for the local environment on port 9334 (and Kibana on port 19334)
            rake elasticsearch:local:8.8.1:daemon    # Boots Elasticsearch 8.8.1 as a background daemon for the local environment on port 9334 (and Kibana on port 19334)
            rake elasticsearch:local:8.8.1:halt      # Halts the Elasticsearch 8.8.1 daemon for the local environment
            rake elasticsearch:local:boot            # Boots Elasticsearch 8.8.1 for the local environment on port 9334 (and Kibana on port 19334)
            rake elasticsearch:local:daemon          # Boots Elasticsearch 8.8.1 as a background daemon for the local environment on port 9334 (and Kibana on port 19334)
            rake elasticsearch:local:halt            # Halts the Elasticsearch 8.8.1 daemon for the local environment
            rake opensearch:example:2.7.0:boot       # Boots OpenSearch 2.7.0 for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
            rake opensearch:example:2.7.0:daemon     # Boots OpenSearch 2.7.0 as a background daemon for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
            rake opensearch:example:2.7.0:halt       # Halts the OpenSearch 2.7.0 daemon for the example environment
            rake opensearch:example:boot             # Boots OpenSearch 2.7.0 for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
            rake opensearch:example:daemon           # Boots OpenSearch 2.7.0 as a background daemon for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
            rake opensearch:example:halt             # Halts the OpenSearch 2.7.0 daemon for the example environment
            rake opensearch:local:2.7.0:boot         # Boots OpenSearch 2.7.0 for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
            rake opensearch:local:2.7.0:daemon       # Boots OpenSearch 2.7.0 as a background daemon for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
            rake opensearch:local:2.7.0:halt         # Halts the OpenSearch 2.7.0 daemon for the local environment
            rake opensearch:local:boot               # Boots OpenSearch 2.7.0 for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
            rake opensearch:local:daemon             # Boots OpenSearch 2.7.0 as a background daemon for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
            rake opensearch:local:halt               # Halts the OpenSearch 2.7.0 daemon for the local environment
          EOS
        end

        it "raises an error when a port number is too low" do
          expect {
            list_datastore_management_tasks do |t|
              t.env_port_mapping = {local: "123"}
            end
          }.to raise_error a_string_including(
            "`env_port_mapping` has invalid ports: ",
            inspect_output_of('{local: "123"}')
          )
        end

        it "raises an error when a port number is too high" do
          expect {
            list_datastore_management_tasks do |t|
              t.env_port_mapping = {local: "45000"}
            end
          }.to raise_error a_string_including(
            "`env_port_mapping` has invalid ports: ",
            inspect_output_of('{local: "45000"}')
          )
        end

        context "when `opensearch_versions` is empty" do
          def run_rake_with_overrides(*cli_args)
            super do |t|
              t.opensearch_versions = []
            end
          end

          it "omits the `opensearch:` tasks" do
            output = list_datastore_management_tasks

            expect(output).to eq(<<~EOS)
              rake elasticsearch:example:8.7.1:boot    # Boots Elasticsearch 8.7.1 for the example environment on port 9612 (and Kibana on port 19612)
              rake elasticsearch:example:8.7.1:daemon  # Boots Elasticsearch 8.7.1 as a background daemon for the example environment on port 9612 (and Kibana on port 19612)
              rake elasticsearch:example:8.7.1:halt    # Halts the Elasticsearch 8.7.1 daemon for the example environment
              rake elasticsearch:example:8.8.1:boot    # Boots Elasticsearch 8.8.1 for the example environment on port 9612 (and Kibana on port 19612)
              rake elasticsearch:example:8.8.1:daemon  # Boots Elasticsearch 8.8.1 as a background daemon for the example environment on port 9612 (and Kibana on port 19612)
              rake elasticsearch:example:8.8.1:halt    # Halts the Elasticsearch 8.8.1 daemon for the example environment
              rake elasticsearch:example:boot          # Boots Elasticsearch 8.8.1 for the example environment on port 9612 (and Kibana on port 19612)
              rake elasticsearch:example:daemon        # Boots Elasticsearch 8.8.1 as a background daemon for the example environment on port 9612 (and Kibana on port 19612)
              rake elasticsearch:example:halt          # Halts the Elasticsearch 8.8.1 daemon for the example environment
              rake elasticsearch:local:8.7.1:boot      # Boots Elasticsearch 8.7.1 for the local environment on port 9334 (and Kibana on port 19334)
              rake elasticsearch:local:8.7.1:daemon    # Boots Elasticsearch 8.7.1 as a background daemon for the local environment on port 9334 (and Kibana on port 19334)
              rake elasticsearch:local:8.7.1:halt      # Halts the Elasticsearch 8.7.1 daemon for the local environment
              rake elasticsearch:local:8.8.1:boot      # Boots Elasticsearch 8.8.1 for the local environment on port 9334 (and Kibana on port 19334)
              rake elasticsearch:local:8.8.1:daemon    # Boots Elasticsearch 8.8.1 as a background daemon for the local environment on port 9334 (and Kibana on port 19334)
              rake elasticsearch:local:8.8.1:halt      # Halts the Elasticsearch 8.8.1 daemon for the local environment
              rake elasticsearch:local:boot            # Boots Elasticsearch 8.8.1 for the local environment on port 9334 (and Kibana on port 19334)
              rake elasticsearch:local:daemon          # Boots Elasticsearch 8.8.1 as a background daemon for the local environment on port 9334 (and Kibana on port 19334)
              rake elasticsearch:local:halt            # Halts the Elasticsearch 8.8.1 daemon for the local environment
            EOS
          end

          it "uses an `elasticsearch:` task for `boot_locally`" do
            expect {
              run_rake_with_overrides("boot_locally", "--dry-run")
            }.to output(a_string_including("Invoke elasticsearch:local:daemon").and(excluding("opensearch"))).to_stderr
          end
        end

        context "when `elasticsearch_versions` is empty" do
          def run_rake_with_overrides(*cli_args)
            super do |t|
              t.elasticsearch_versions = []
            end
          end

          it "omits the `elasticsearch:` tasks" do
            output = list_datastore_management_tasks

            expect(output).to eq(<<~EOS)
              rake opensearch:example:2.7.0:boot    # Boots OpenSearch 2.7.0 for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
              rake opensearch:example:2.7.0:daemon  # Boots OpenSearch 2.7.0 as a background daemon for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
              rake opensearch:example:2.7.0:halt    # Halts the OpenSearch 2.7.0 daemon for the example environment
              rake opensearch:example:boot          # Boots OpenSearch 2.7.0 for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
              rake opensearch:example:daemon        # Boots OpenSearch 2.7.0 as a background daemon for the example environment on port 9612 (and OpenSearch Dashboards on port 19612)
              rake opensearch:example:halt          # Halts the OpenSearch 2.7.0 daemon for the example environment
              rake opensearch:local:2.7.0:boot      # Boots OpenSearch 2.7.0 for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
              rake opensearch:local:2.7.0:daemon    # Boots OpenSearch 2.7.0 as a background daemon for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
              rake opensearch:local:2.7.0:halt      # Halts the OpenSearch 2.7.0 daemon for the local environment
              rake opensearch:local:boot            # Boots OpenSearch 2.7.0 for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
              rake opensearch:local:daemon          # Boots OpenSearch 2.7.0 as a background daemon for the local environment on port 9334 (and OpenSearch Dashboards on port 19334)
              rake opensearch:local:halt            # Halts the OpenSearch 2.7.0 daemon for the local environment
            EOS
          end

          it "uses an `opensearch:` task for `boot_locally`" do
            expect {
              run_rake_with_overrides("boot_locally", "--dry-run")
            }.to output(a_string_including("Invoke opensearch:local:daemon").and(excluding("elasticsearch"))).to_stderr
          end
        end

        context "when both `opensearch_versions` and `elasticsearch_versions` are empty" do
          def run_rake_with_overrides(*cli_args)
            super do |t|
              t.elasticsearch_versions = []
              t.opensearch_versions = []
            end
          end

          it "raises an error to indicate that the user needs to select some versions" do
            expect {
              list_datastore_management_tasks
            }.to raise_error a_string_including("Both `elasticsearch_versions` and `opensearch_versions` are empty")
          end
        end

        def list_datastore_management_tasks(&block)
          run_rake_with_overrides("-T", "search:", &block)
        end
      end

      def run_rake_with_overrides(*cli_args)
        run_rake(*cli_args) do |output|
          RakeTasks.new(
            local_config_yaml: config_dir / "settings" / "development.yaml",
            path_to_schema: config_dir / "schema.rb"
          ) do |t|
            t.env_port_mapping = {"example" => 9612}
            t.elasticsearch_versions = ["8.7.1", "8.8.1"]
            t.opensearch_versions = ["2.7.0"]
            t.output = output

            yield t if block_given?
          end
        end
      end

      def run_rake_with_yaml_changes(*cli_args)
        base_yaml = ::YAML.load((config_dir / "settings" / "development.yaml").read, aliases: true)
        updated_yaml = yield base_yaml

        ::Dir.mktmpdir do |tmp_dir|
          ::Dir.chdir(tmp_dir) do
            ::File.write("local.yaml", ::YAML.dump(updated_yaml))

            run_rake(*cli_args) do
              RakeTasks.new(
                local_config_yaml: "local.yaml",
                path_to_schema: config_dir / "schema.rb"
              )
            end
          end
        end
      end
    end
  end
end
