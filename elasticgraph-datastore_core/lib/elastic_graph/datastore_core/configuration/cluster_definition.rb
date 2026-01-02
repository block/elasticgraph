# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class DatastoreCore
    module Configuration
      class ClusterDefinition < ::Data.define(:url, :backend_client_class, :settings)
        BACKEND_CLIENT_CLASSES = {
          "elasticsearch" => "ElasticGraph::Elasticsearch::Client",
          "opensearch" => "ElasticGraph::OpenSearch::Client"
        }

        def self.from_hash(hash)
          backend_name = hash.fetch("backend")
          require "elastic_graph/#{backend_name}/client"
          backend_client_class = ::Object.const_get(BACKEND_CLIENT_CLASSES.fetch(backend_name))

          new(
            url: hash.fetch("url"),
            backend_client_class: backend_client_class,
            settings: hash.fetch("settings")
          )
        end

        def self.definitions_by_name_hash_from(cluster_def_hash_by_name)
          cluster_def_hash_by_name.transform_values do |cluster_def_hash|
            from_hash(cluster_def_hash)
          end
        end
      end
    end
  end
end
