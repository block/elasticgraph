# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/cli"
require "tempfile"

module ElasticGraph
  ::RSpec.describe CLI, "new command", :in_temp_dir do
    it "initializes a new ElasticGraph project" do
      override_gemfile_to_use_local_elasticgraph_gems do
        output = run_new("musical_artists1")

        expect(output.lines.first(18).join).to eq <<~EOS
          Creating a new OpenSearch ElasticGraph project called 'musical_artists1' at: #{::Dir.pwd}/musical_artists1
                create  musical_artists1
                create  musical_artists1/.gitignore
                create  musical_artists1/.standard.yml
                create  musical_artists1/Gemfile
                create  musical_artists1/README.md
                create  musical_artists1/Rakefile
                create  musical_artists1/config/queries/example_client/FindArtist.graphql
                create  musical_artists1/config/queries/example_client/ListArtistAlbums.graphql
                create  musical_artists1/config/schema.rb
                create  musical_artists1/config/schema/artists.rb
                create  musical_artists1/config/settings/local.yaml
                create  musical_artists1/spec/project_spec.rb
                create  musical_artists1/lib/musical_artists1
                create  musical_artists1/lib/musical_artists1/factories.rb
                create  musical_artists1/lib/musical_artists1/fake_data_batch_generator.rb
                create  musical_artists1/lib/musical_artists1/shared_factories.rb
                   run  bundle install from "./musical_artists1"
        EOS

        bundle_exec_rake_line = output.lines.index { |l| l =~ /bundle exec rake/ }
        expect(output.lines[bundle_exec_rake_line..(bundle_exec_rake_line + 16)].join).to eq <<~EOS
                   run  bundle exec rake schema_artifacts:dump query_registry:dump_variables:all build from "./musical_artists1"
          Dumped schema artifact to `config/schema/artifacts/datastore_config.yaml`.
          Dumped schema artifact to `config/schema/artifacts/json_schemas.yaml`.
          Dumped schema artifact to `config/schema/artifacts/json_schemas_by_version/v1.yaml`.
          Dumped schema artifact to `config/schema/artifacts/runtime_metadata.yaml`.
          Dumped schema artifact to `config/schema/artifacts/schema.graphql`.
          - Dumped `config/queries/example_client/FindArtist.variables.yaml`.
          - Dumped `config/queries/example_client/ListArtistAlbums.variables.yaml`.
          Inspecting 8 files
          ........

          8 files inspected, no offenses detected
          For client `example_client`:
            - FindArtist.graphql (1 operation):
              - FindArtist: ✅
            - ListArtistAlbums.graphql (1 operation):
              - ListArtistAlbums: ✅
        EOS

        expect(output.lines.last(6).join).to eq <<~EOS
          Successfully bootstrapped 'musical_artists1' as a new OpenSearch ElasticGraph project.
          Next steps:
            1. cd musical_artists1
            2. Run `bundle exec rake boot_locally` to try it out in your browser.
            3. Run `bundle exec rake -T` to view other available tasks.
            4. Customize your new project as needed. (Search for `TODO` to find things that need updating.)
        EOS

        # Verify that all ERB templates rendered properly. If any files had ERB template tags (e.g. `<%= foo %>`)
        # but were not named with the proper `.tt` file extension, then thor would copy them without rendering them
        # as ERB. This would catch it.
        expect(all_committed_code_in("musical_artists1")).to exclude("<%", "%>")

        # Verify that the only TODO comments in the project comte from our template, not from our generated artifacts.
        expect(todo_comments_in("musical_artists1").join("\n")).to eq(todo_comments_in(CLI.source_root).join("\n"))
      end
    end

    it "aborts if given an invalid datastore option" do
      expect {
        ::ElasticGraph::CLI.start(["new", "artists", "--datastore", "elasticsearc"])
      }.to fail_with(
        a_string_including("Invalid datastore option: elasticsearc. Must be elasticsearch or opensearch.")
      )
    end

    it "requires the app name to be in snake_case form, starting with a letter" do
      expect {
        ::ElasticGraph::CLI.start(["new", "musical-artists"])
      }.to fail_with(
        a_string_including("App name must start with a letter and be in `snake_case` form but was not: `musical-artists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "musicalArtists"])
      }.to fail_with(
        a_string_including("App name must start with a letter and be in `snake_case` form but was not: `musicalArtists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "MusicalArtists"])
      }.to fail_with(
        a_string_including("App name must start with a letter and be in `snake_case` form but was not: `MusicalArtists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "Musical-Artists"])
      }.to fail_with(
        a_string_including("App name must start with a letter and be in `snake_case` form but was not: `Musical-Artists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "_musical_artists"])
      }.to fail_with(
        a_string_including("App name must start with a letter and be in `snake_case` form but was not: `_musical_artists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "1musical_artists"])
      }.to fail_with(
        a_string_including("App name must start with a letter and be in `snake_case` form but was not: `1musical_artists`.")
      )
    end

    def fail_with(message)
      raise_error(::SystemExit).and output(message).to_stderr
    end

    def run_new(*argv)
      captured_io = ::Tempfile.new("captured_io")
      captured_io.sync = true

      original_stdout = $stdout.clone
      original_stderr = $stderr.clone
      $stdout.reopen(captured_io)
      $stderr.reopen(captured_io)

      begin
        ::ElasticGraph::CLI.start(["new", *argv])
        # :nocov: -- rescue clause is only executed when a test fails.
      rescue ::Exception => ex # standard:disable Lint/RescueException
        captured_io.rewind
        output = captured_io.read

        $stdout.reopen(original_stdout)
        $stdout.puts <<~EOS
          Encountered an exception: #{ex.class}: #{ex.message}.

          Output before exception:
          #{output}
        EOS

        raise ex
        # :nocov:
      else
        captured_io.rewind
        captured_io.read
      ensure
        $stdout.reopen(original_stdout)
        $stderr.reopen(original_stderr)
        captured_io.close
        captured_io.unlink
      end
    end

    # When running tests here, we want to force bundler to use our local gems
    # instead of installing the ElasticGraph gems from rubygems.org so that our
    # bootstrapped files can reference and use ElasticGraph files that have not
    # yet been released (but are available locally, and will be in the next release).
    #
    # Here we hook into the call to `ElasticGraph.setup_env` in order to override its
    # `gemfile_elasticgraph_details_code_snippet`, to force it to use oru local gems.
    def override_gemfile_to_use_local_elasticgraph_gems
      with_env "ELASTICGRAPH_GEMS_PATH" => CommonSpecHelpers::REPO_ROOT do
        yield
      end
    end

    def all_committed_code_in(dir)
      ::Dir.chdir(dir) { `git ls-files -z | xargs -0 cat` }
    end

    def todo_comments_in(dir)
      ::Dir.chdir(dir) do
        `git grep TODO`.split("\n").map do |match|
          match.sub(/^[^:]+:\s*/, "")
        end
      end
    end
  end
end
