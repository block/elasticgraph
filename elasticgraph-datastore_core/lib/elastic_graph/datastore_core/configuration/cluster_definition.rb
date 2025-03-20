# Copyright 2024 - 2025 Block, Inc.
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
        def self.from_hash(hash)
          extra_keys = hash.keys - EXPECTED_KEYS

          unless extra_keys.empty?
            raise Errors::ConfigError, "Unknown `datastore.clusters` config settings: #{extra_keys.join(", ")}"
          end

          backend_name = hash["backend"]
          backend_client_class =
            case backend_name
            when "elasticsearch"
              require "elastic_graph/elasticsearch/client"
              Elasticsearch::Client
            when "opensearch"
              require "elastic_graph/opensearch/client"
              OpenSearch::Client
            else
              raise Errors::ConfigError, "Unknown `datastore.clusters` backend: `#{backend_name}`. Valid backends are `elasticsearch` and `opensearch`."
            end

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

        EXPECTED_KEYS = members.map(&:to_s) - ["backend_client_class"] + ["backend"]
      end
    end
  end
end
