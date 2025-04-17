# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/spec_support/builds_admin"
require "yaml"

module ElasticGraph
  # Helper class to manage the datastore index configuration for our tests.
  # Re-creating the indices, while not a super slow operation, adds 1-2 seconds to
  # a test run, and it's something we generally want to avoid doing on each test run
  # unless something has actually changed.  Our approach here is to store a state
  # file in a git-ignored directory. Our `boot_prep_for_tests` rake task (called
  # when booting a datastore) deletes the file each time a datastore is booted.
  # If the file already exists and matches the desired index state, we can avoid
  # recreating the indices.
  #
  # The assumption here is that the state file will not get out of sync with the state
  # of the indices in the datastore. As long as the engineer isn't manually changing
  # the index configuration (which we don't support), this should work.
  class ClusterConfigurationManager
    include CommonSpecHelpers
    include BuildsAdmin
    attr_reader :admin
    attr_accessor :state_file_name

    def initialize(version:, datastore_backend:, admin: nil, state_file_name: "elasticgraph_configured_indices.yaml")
      @version = version
      @admin = admin || build_admin(datastore_backend: datastore_backend)
      self.state_file_name = state_file_name
    end

    def manage_cluster
      without_vcr do
        admin.datastore_core.clients_by_name.values.each do |client|
          client.delete_indices("unique_index_*")
          client.delete_index_template("unique_index_*")
        end
      end

      # :nocov: -- to save time, avoids executing when the indices are already configured correctly
      if !File.exist?(state_file_path) || current_cluster_state != File.read(state_file_path)
        recreate_index_configuration
        ::FileUtils.mkdir_p(File.dirname(state_file_path))
        File.write(state_file_path, current_cluster_state)
      end
      # :nocov:

      @version + current_cluster_state # return the current state
    end

    private

    # :nocov: -- to save time, avoids executing when the indices are already configured correctly
    def recreate_index_configuration
      without_vcr do
        start = ::Time.now

        notify_recreating_cluster_configuration

        admin.datastore_core.clients_by_name.values.each do |client|
          index_definitions.each { |index_def| index_def.delete_from_datastore(client) }
        end

        admin.cluster_configurator.configure_cluster(StringIO.new)

        notify_recreated_cluster_configuration(::Time.now - start)
      end
    end

    def notify_recreating_cluster_configuration
      print "\nRecreating cluster configuration (for index definitions: #{index_definitions.map(&:name)})..."
    end

    def notify_recreated_cluster_configuration(duration)
      puts "done in #{RSpec::Core::Formatters::Helpers.format_duration(duration)}."
    end
    # :nocov:

    STATE_FILE_DIR = "tmp/datastore-state-files"

    def state_file_path
      @state_file_path ||= ::File.join(CommonSpecHelpers::REPO_ROOT, STATE_FILE_DIR, state_file_name)
    end

    def current_cluster_state
      @current_cluster_state ||= YAML.dump({
        "datastore_scripts" => datastore_scripts,
        "indices_by_name" => admin.schema_artifacts.indices.merge(admin.schema_artifacts.index_templates)
      })
    end

    # :nocov: -- to save time, avoids executing when the indices are already configured correctly.
    def index_definitions
      @index_definitions ||= admin.datastore_core.index_definitions_by_name.values
    end
    # :nocov:

    def datastore_scripts
      @datastore_scripts ||= admin.schema_artifacts.datastore_scripts
    end

    # :nocov: -- to save time, avoids executing when the indices are already configured correctly
    def without_vcr
      return yield unless defined?(::VCR) # since we support running w/o VCR.
      VCR.turned_off { yield }
    end
    # :nocov:
  end
end
