# frozen_string_literal: true

module ElasticGraph
  class WarehouseLambda
    module IndexerExtension
      attr_accessor :warehouse_lambda

      def datastore_router
        warehouse_lambda.warehouse_dumper
      end
    end
  end
end
