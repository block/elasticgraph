# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/query_interceptor/config"
require "elastic_graph/query_interceptor/datastore_query_adapter"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module QueryInterceptor
    module GraphQLExtension
      def datastore_query_adapters
        @datastore_query_adapters ||= begin
          runtime_metadata_configs = runtime_metadata.graphql_extension_modules.filter_map do |ext_mod|
            Support::HashUtil.stringify_keys(ext_mod.config) if ext_mod.extension_class == GraphQLExtension
          end

          interceptors = Config
            .from_parsed_yaml(config.extension_settings, parsed_runtime_metadata_hashes: runtime_metadata_configs)
            .interceptors
            .map { |data| data.klass.new(elasticgraph_graphql: self, config: data.config) }

          super + [DatastoreQueryAdapter.new(interceptors)]
        end
      end
    end
  end
end
