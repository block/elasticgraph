# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/spec_support/parallel_spec_runner/datastore_client_adapter"

module ElasticGraph
  module ParallelSpecRunner
    # This adapter hooks into the instantiation of new datastore clients from `DatastoreCore` and wraps them with
    # `DatastoreClientAdapter` so that all datastore clients have the patched behavior necessary for parallel spec runs.
    module DatastoreCoreAdapter
      def clients_by_name
        @clients_by_name ||= super.transform_values do |client|
          DatastoreClientAdapter.new(client)
        end
      end

      DatastoreCore.prepend(self)
    end
  end
end
