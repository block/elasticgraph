# Copyright 2024 Block, Inc.
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
      override_gemfile_to_use_local_elasticgraph_gems

      output = run_new("musical_artists")

      expect(output.lines.first(18).join).to eq <<~EOS
        Creating a new ElasticGraph app called 'musical_artists' at: #{::Dir.pwd}/musical_artists
              create  musical_artists
              create  musical_artists/.gitignore
              create  musical_artists/.standard.yml
              create  musical_artists/Gemfile
              create  musical_artists/README.md
              create  musical_artists/Rakefile
              create  musical_artists/config/queries/example_client/FindArtist.graphql
              create  musical_artists/config/queries/example_client/ListArtistAlbums.graphql
              create  musical_artists/config/schema.rb
              create  musical_artists/config/schema/artists.rb
              create  musical_artists/config/settings/local.yaml
              create  musical_artists/spec/project_spec.rb
              create  musical_artists/lib/musical_artists
              create  musical_artists/lib/musical_artists/factories.rb
              create  musical_artists/lib/musical_artists/fake_data_batch_generator.rb
              create  musical_artists/lib/musical_artists/shared_factories.rb
                 run  bundle install from "./musical_artists"
      EOS

      bundle_exec_rake_line = output.lines.index { |l| l =~ /bundle exec rake/ }
      expect(output.lines[bundle_exec_rake_line..(bundle_exec_rake_line + 16)].join).to eq <<~EOS
                 run  bundle exec rake schema_artifacts:dump query_registry:dump_variables:all build from "./musical_artists"
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
        Successfully bootstrapped 'musical_artists' as a new ElasticGraph project.
        Next steps:
          1. cd musical_artists
          2. Run `bundle exec rake boot_locally` to try it out in your browser.
          3. Run `bundle exec rake -T` to view other available tasks.
          4. Customize your new project as needed.
      EOS
    end

    it "aborts if given an invalid datastore option" do
      expect {
        ::ElasticGraph::CLI.start(["new", "artists", "--datastore", "elasticsearc"])
      }.to fail_with(
        a_string_including("Invalid datastore option: elasticsearc. Must be elasticsearch or opensearch.")
      )
    end

    it "requires the app name to be in snake_case form" do
      expect {
        ::ElasticGraph::CLI.start(["new", "musical-artists"])
      }.to fail_with(
        a_string_including("App name must be in `snake_case` form but was not: `musical-artists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "musicalArtists"])
      }.to fail_with(
        a_string_including("App name must be in `snake_case` form but was not: `musicalArtists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "MusicalArtists"])
      }.to fail_with(
        a_string_including("App name must be in `snake_case` form but was not: `MusicalArtists`.")
      )

      expect {
        ::ElasticGraph::CLI.start(["new", "Musical-Artists"])
      }.to fail_with(
        a_string_including("App name must be in `snake_case` form but was not: `Musical-Artists`.")
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
    # Here we hook into the call our CLI makes to `Bundler.with_unbundled_env` to
    # edit the `Gemfile` just before `bundle install` gets run.
    def override_gemfile_to_use_local_elasticgraph_gems
      allow(::Bundler).to receive(:with_unbundled_env).and_wrap_original do |original, &block|
        gemfile_contents = ::File.read("Gemfile")

        # This pattern matches one or more consecutive lines starting with:
        #   gem "elasticgraph-..."
        # capturing them as a single chunk (capture group 1).
        pattern = /
        (
          ^\s*gem\s+"elasticgraph-[^"]+"[^\n]*\n
          (?:^\s*gem\s+"elasticgraph-[^"]+"[^\n]*\n)*
        )
        /mx

        new_contents = gemfile_contents.gsub(pattern) do |eg_gem_section|
          <<~EOS

            git "file://#{CommonSpecHelpers::REPO_ROOT}" do
              #{eg_gem_section.delete_prefix("\n").split("\n").join("\n  ")}
            end
          EOS
        end

        ::File.write("Gemfile", new_contents)

        original.call(&block)
      end
    end
  end
end
