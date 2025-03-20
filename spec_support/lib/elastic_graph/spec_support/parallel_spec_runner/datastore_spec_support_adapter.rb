# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/parallel_spec_runner/datastore_client_adapter"
require "elastic_graph/spec_support/uses_datastore"

module ElasticGraph
  module ParallelSpecRunner
    # This adapter hooks into the instantiation of new datastore clients from `DatastoreSpecSupport` and wraps them with
    # `DatastoreClientAdapter` so that all datastore clients have the patched behavior necessary for parallel spec runs.
    module DatastoreSpecSupportAdapter
      def new_datastore_client(...)
        DatastoreClientAdapter.new(super)
      end

      DatastoreSpecSupport.prepend(self)
    end
  end
end
