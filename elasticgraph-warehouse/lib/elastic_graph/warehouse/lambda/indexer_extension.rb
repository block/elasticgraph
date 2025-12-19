# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Warehouse
    class Lambda
      # Module that extends the Indexer to use the warehouse dumper instead of the datastore router.
      # @private
      module IndexerExtension
        # @dynamic warehouse_lambda, warehouse_lambda=
        attr_accessor :warehouse_lambda

        def datastore_router
          warehouse_lambda.warehouse_dumper
        end
      end
    end
  end
end
