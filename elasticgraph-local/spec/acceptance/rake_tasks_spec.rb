# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/local/rake_tasks"
require "elastic_graph/schema_definition/rake_tasks"
require "json"
require "net/http"
require "pathname"
require "tmpdir"

module ElasticGraph
  module Local
    RSpec.describe RakeTasks, :rake_task, :factories do
      # Some tests here rely on being run from the repo root, due to paths from our
      # config files being relative to the root.
      around { |ex| Dir.chdir(CommonSpecHelpers::REPO_ROOT, &ex) }

      it "supports fully booting from scratch via a single `boot_locally` rake task" do
        rack_port = 9620
        kill_daemon_after "rackup.pid" do |pid_file|
          halt_datastore_daemon_after :elasticsearch do
            output = run_rake "boot_locally[#{rack_port}, --daemonize --pid #{pid_file}, no_open]"

            expect(output).to include(
              # It boots Elasticsearch...
              "Success! elasticsearch", "has been booted for the local environment",
              # ...dumps schema artifacts...
              "datastore_config.yaml` is already up to date",
              # ...configures Elasticsearch...
              "Updated index template: `widgets`",
              # ...indexes a document...
              "Published batch of 1 document"
            )

            # ...and then boots GraphiQL, but given how it boots with Rake's `sh`, it's not captured in `output`.

            wait_for_server_readiness(rack_port, path: "/graphql")

            # Validate that we can query the booted server!
            response = query_server_on(rack_port, path: "/graphql?query=#{::CGI.escape(<<~EOS)}")
              query {
                widgets {
                  total_edge_count
                }
              }
            EOS

            expect(response).to eq({"data" => {"widgets" => {"total_edge_count" => 1}}})
          end
        end
      end

      context "when the datastore is not running" do
        it "boots the datastore as a daemon to support booting GraphiQL" do
          halt_datastore_daemon_after :elasticsearch do |datastore_port|
            expect {
              kill_daemon_after("rackup.pid") do |pid_file|
                run_rake "boot_graphiql[9621, --daemonize --pid #{pid_file}, no_open]"
              end
            }.to change { datastore_running? }.from(false).to(true)
          end
        end

        it "boots the datastore as a daemon to support configuring the datastore" do
          halt_datastore_daemon_after :elasticsearch do
            expect {
              run_rake "clusters:configure:dry_run"
            }.to change { datastore_running? }.from(false).to(true)
          end

          halt_datastore_daemon_after :elasticsearch do
            expect {
              run_rake "clusters:configure:perform"
            }.to change { datastore_running? }.from(false).to(true)
          end
        end

        it "boots the datastore as a daemon to support indexing data locally" do
          halt_datastore_daemon_after :elasticsearch do
            expect {
              run_rake "index_fake_data:widgets[1]"
            }.to change { datastore_running? }.from(false).to(true)
          end
        end

        def datastore_running?
          local_port = 9334
          expect(query_server_on(local_port).keys).to include("version")
          true
        rescue Errno::ECONNREFUSED, EOFError
          false
        end
      end

      describe "elasticsearch/opensearch tasks" do
        it "times out if booting takes too long" do
          expect {
            run_rake "elasticsearch:example:9.0.0:daemon", daemon_timeout: 0.1
          }.to raise_error a_string_including("Timed out after 0.1 seconds.")
        end
      end

      def run_rake(*cli_args, daemon_timeout: nil, batch_size: 1)
        outer_output = nil

        config_dir = ::Pathname.new(::File.join(CommonSpecHelpers::REPO_ROOT, "config"))

        # Give a longer timeout to CI than we tolerate locally.
        # :nocov: -- only one of the two sides of the ternary gets covered.
        daemon_timeout ||= ENV["CI"] ? 120 : 60
        # :nocov:

        # We need to run without bundler because some tasks shell out and run `bundle exec` and
        # the local bundler we're running within could interfere.
        without_bundler do
          super(*cli_args) do |output|
            outer_output = output

            RakeTasks.new(
              local_config_yaml: config_dir / "settings" / "development.yaml",
              path_to_schema: config_dir / "schema.rb"
            ) do |t|
              t.index_document_sizes = true
              t.schema_element_name_form = :snake_case
              t.env_port_mapping = {"example" => 9615}
              t.elasticsearch_versions = ["8.18.0", "9.0.0"]
              t.opensearch_versions = ["2.7.0"]
              t.output = output
              t.daemon_timeout = daemon_timeout

              t.define_fake_data_batch_for(:widgets) do
                Array.new(batch_size) { build(:widget) }
              end
            end
          end
        end
      rescue ::Timeout::Error => e
        raise ::Timeout::Error.new("#{outer_output.string}\n\n#{e.message}")
      end

      def without_bundler
        # :nocov: -- Bundler doesn't have to be used to run our test suite, so we handle both cases here
        #            But only one branch is taken on a given run of the test suite.
        return yield unless defined?(::Bundler)
        ::Bundler.with_original_env { yield }
        # :nocov:
      end

      def query_server_on(port, path: "/", parse_json: true)
        response = ::Net::HTTP.start("localhost", port) do |http|
          http.read_timeout = 2
          http.get(path)
        end

        parse_json ? ::JSON.parse(response.body) : response.body
      end

      def kill_daemon_after(pid_name)
        ::Dir.mktmpdir do |dir|
          pid_file = "#{dir}/#{pid_name}"

          begin
            yield pid_file
          ensure
            # :nocov: -- under normal conditions some branches here aren't used
            pid = begin
              pid_contents = ::File.read(pid_file)
              Integer(pid_contents)
            rescue
              nil
            end

            ::Process.kill(9, pid) if pid
            ::FileUtils.rm_rf(pid_file) # Necessary to avoid an Errno::ENOTEMPTY
            # :nocov:
          end
        end
      end

      def halt_datastore_daemon_after(datastore)
        yield
      ensure
        run_rake "#{datastore}:local:halt"
      end

      def wait_for_server_readiness(port, path:)
        started_waiting_at = ::Time.now
        last_error = nil

        # Wait up to 30 seconds on CI or 5 seconds locally. (We give CI more time because we have occasionally seen it
        # fail at 10 seconds there, and can tolerate it taking longer. Locally you want quick feedback when you run these
        # tests, you want to know if a server didn't boot right away, and it doesn't need to need more than 5 seconds).
        # :nocov: -- we give CI more time than we do locally, so only one branch will be covered.
        iterations = ENV["CI"] ? 300 : 50
        # :nocov:

        iterations.times do
          query_server_on(port, path: path, parse_json: false)
        rescue Errno::ECONNREFUSED, EOFError => e
          # :nocov: -- not always covered (depends on if the rack server is ready).
          last_error = e
          sleep 0.1
          # :nocov:
        else
          return
        end

        # :nocov: -- only hit when the server fails to boot (which doesn't happen on a successful test run)
        raise "Server on port #{port} failed to boot in #{::Time.now - started_waiting_at} seconds; Last error from #{path} was: #{last_error.class}: #{last_error.message}"
        # :nocov:
      end
    end
  end
end
