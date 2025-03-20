# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/cluster_configuration_manager"

module ElasticGraph
  module ParallelSpecRunner
    module ClusterConfigurationManagerAdapter
      def initialize(...)
        super

        # We need to track the state of each scoped set of indices separately, so that we can appropriately recreate the indices
        # for a particular index prefix at the right times. To achieve that, we prepend the `state_file_name` with the index prefix here.
        self.state_file_name = "#{ParallelSpecRunner.index_prefix}_#{state_file_name}"
      end

      def notify_recreating_cluster_configuration
        # The message that is normally printed here is "part 1" with the `notify_recreated_cluster_configuration` message completing
        # the notification and reporting how long it took. During parallel test execution, we don't want the messages to be split
        # like that: it leads to noisy, confusing output. Instead, we've merged the normal contents of this notification into
        # `notify_recreated_cluster_configuration` below so that we provide a single notification with all the information.
      end

      # :nocov: -- whether this is called depends on whether the datastore is already fully configured or not
      def notify_recreated_cluster_configuration(duration)
        puts "\nRecreated test env #{ParallelSpecRunner.test_env_number} cluster configuration (for index definitions: " \
          "#{index_definitions.map(&:name)}) in #{RSpec::Core::Formatters::Helpers.format_duration(duration)}."
      end
      # :nocov:

      ClusterConfigurationManager.prepend(self)
    end
  end
end
