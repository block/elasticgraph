# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/config"
require "elastic_graph/datastore_core/configuration/cluster_definition"
require "elastic_graph/datastore_core/configuration/index_definition"
require "elastic_graph/errors"

module ElasticGraph
  class DatastoreCore
    # Defines the configuration related to datastores.
    class Config < Support::Config.define(:client_faraday_adapter, :clusters, :index_definitions, :log_traffic, :max_client_retries)
      all_json_schema_types = ["array", "string", "number", "boolean", "object", "null"]

      json_schema at: "datastore",
        optional: false,
        description: "Configuration for datastore connections and index definitions used by all parts of ElasticGraph.",
        properties: {
          client_faraday_adapter: {
            type: "object",
            description: "Configuration of the faraday adapter to use with the datastore client.",
            properties: {
              name: {
                type: ["string", "null"],
                minLength: 1,
                description: "The faraday adapter to use with the datastore client, such as `httpx` or `typhoeus`.",
                examples: ["net_http", "httpx", "typhoeus", nil],
                default: nil
              },
              require: {
                type: ["string", "null"],
                minLength: 1,
                description: "A Ruby library to require which provides the named adapter (optional).",
                examples: ["httpx/adapters/faraday"],
                default: nil
              }
            },
            default: {"name" => nil, "require" => nil},
            examples: [
              {"name" => "net_http"},
              {"name" => "httpx", "require" => "httpx/adapters/faraday"}
            ]
          },

          clusters: {
            type: "object",
            description: "Map of datastore cluster definitions, keyed by cluster name. The names will be referenced within " \
              "`index_definitions` by `query_cluster` and `index_into_clusters` to identify datastore clusters.",
            patternProperties: {
              /.+/.source => {
                type: "object",
                description: "Configuration for a specific datastore cluster.",
                examples: [{
                  url: "http://localhost:9200",
                  backend: "elasticsearch",
                  settings: {"cluster.max_shards_per_node" => 2000}
                }],
                properties: {
                  url: {
                    type: "string",
                    minLength: 1,
                    description: "The URL of the datastore cluster.",
                    examples: ["http://localhost:9200", "https://my-cluster.example.com:9200"]
                  },
                  backend: {
                    enum: ["elasticsearch", "opensearch"],
                    description: "Determines whether `elasticgraph-elasticsearch` or `elasticgraph-opensearch` is used for the datastore client.",
                    examples: ["elasticsearch", "opensearch"]
                  },
                  settings: {
                    type: "object",
                    description: "Datastore settings in flattened (i.e. dot-separated) name form.",
                    patternProperties: {/.+/.source => {"type" => all_json_schema_types}},
                    examples: [{"cluster.max_shards_per_node" => 2000}],
                    default: {} # : untyped
                  }
                },
                required: ["url", "backend"]
              }
            },
            examples: [{
              "main" => {
                url: "http://localhost:9200",
                backend: "elasticsearch",
                settings: {"cluster.max_shards_per_node" => 2000}
              }
            }]
          },

          index_definitions: {
            type: "object",
            description: "Map of index definition names to `IndexDefinition` objects containing customizations for the named index definitions for this environment.",
            patternProperties: {
              /.+/.source => {
                type: "object",
                description: "Configuration for a specific index definition.",
                examples: [example_index_def = {
                  "query_cluster" => "main",
                  "index_into_clusters" => ["main"],
                  "ignore_routing_values" => ["ABC1234567"], # : untyped
                  "setting_overrides" => {
                    "number_of_shards" => 256
                  },
                  "setting_overrides_by_timestamp" => {
                    "2022-01-01T00:00:00Z" => {
                      "number_of_shards" => 64
                    },
                    "2023-01-01T00:00:00Z" => {
                      "number_of_shards" => 96
                    },
                    "2024-01-01T00:00:00Z" => {
                      "number_of_shards" => 128
                    }
                  },
                  "custom_timestamp_ranges" => [
                    {
                      "index_name_suffix" => "before_2022",
                      "lt" => "2022-01-01T00:00:00Z",
                      "setting_overrides" => {"number_of_shards" => 32}
                    },
                    {
                      "index_name_suffix" => "after_2026",
                      "gte" => "2027-01-01T00:00:00Z",
                      "setting_overrides" => {"number_of_shards" => 32}
                    }
                  ]
                }],
                properties: {
                  query_cluster: {
                    type: "string",
                    description: "Named search cluster to be used for queries on this index. The value must match be a key in the `clusters` map.",
                    examples: ["main", "search_cluster"]
                  },
                  skip_meta_sources_lookup: {
                    type: "boolean",
                    description: "If true, skip `_meta.ElasticGraph.sources` lookup; determine incomplete-docs purely from current_sources.",
                    default: false,
                    examples: [false, true]
                  },
                  index_into_clusters: {
                    type: "array",
                    items: {type: "string", minLength: 1},
                    description: "Named search clusters to index data into. The values must match keys in the `clusters` map.",
                    examples: [["main"], ["cluster1", "cluster2"]]
                  },
                  ignore_routing_values: {
                    type: "array",
                    items: {"type" => "string"},
                    description: "Shard routing values for which the data should be spread across all shards instead of concentrating it " \
                      "on a single shard. This is intended to be used when a handful of known routing value contain such a large portion " \
                      "of the dataset that it extremely lopsided shards would result. Spreading the data across all shards may perform " \
                      "better.",
                    default: [], # : untyped
                    examples: [
                      [], # : untyped
                      ["mega_tenant1", "mega_tenant2"]
                    ]
                  },
                  setting_overrides: {
                    type: "object",
                    description: "Overrides for index (or index template) settings. The settings specified here will override any settings " \
                      "specified on the Ruby schema definition. This is commonly used to configure a different `number_of_shards` in each " \
                      "environment. An `index.` prefix will be added to the names of all settings before submitting them to the datastore.",
                    patternProperties: {/.+/.source => {"type" => all_json_schema_types}},
                    default: {}, # :untyped
                    examples: [{"number_of_shards" => 5}]
                  },
                  setting_overrides_by_timestamp: {
                    type: "object",
                    description: "Overrides for index template settings for specific dates, allowing variation of settings for different " \
                      "rollover indices. This is commonly used to configure a different `number_of_shards` for each year or month when " \
                      "using yearly or monthly rollover.",
                    propertyNames: {type: "string", format: "date-time"},
                    additionalProperties: {type: "object", patternProperties: {/.+/.source => {"type" => all_json_schema_types}}},
                    default: {}, # : untyped
                    examples: [{"2025-01-01T00:00:00Z" => {"number_of_shards" => 10}}]
                  },
                  custom_timestamp_ranges: {
                    type: "array",
                    description: "Array of custom timestamp ranges that allow different index settings for specific time periods.",
                    items: {
                      type: "object",
                      properties: {
                        index_name_suffix: {
                          type: "string",
                          description: "Suffix to append to the index name for this custom range.",
                          examples: ["before_2020", "after_2027"]
                        },
                        setting_overrides: {
                          type: "object",
                          description: "Setting overrides for this custom timestamp range.",
                          patternProperties: {/.+/.source => {"type" => all_json_schema_types}},
                          examples: [{"number_of_shards" => 17}, {"number_of_replicas" => 2}]
                        },
                        lt: {
                          type: ["string", "null"],
                          format: "date-time",
                          description: "Less than timestamp boundary (ISO 8601 format).",
                          examples: ["2015-01-01T00:00:00Z", "2020-12-31T23:59:59Z"],
                          default: nil
                        },
                        lte: {
                          type: ["string", "null"],
                          format: "date-time",
                          description: "Less than or equal timestamp boundary (ISO 8601 format).",
                          examples: ["2015-01-01T00:00:00Z", "2020-12-31T23:59:59Z"],
                          default: nil
                        },
                        gt: {
                          type: ["string", "null"],
                          format: "date-time",
                          description: "Greater than timestamp boundary (ISO 8601 format).",
                          examples: ["2015-01-01T00:00:00Z", "2020-01-01T00:00:00Z"],
                          default: nil
                        },
                        gte: {
                          type: ["string", "null"],
                          format: "date-time",
                          description: "Greater than or equal timestamp boundary (ISO 8601 format).",
                          examples: ["2015-01-01T00:00:00Z", "2020-01-01T00:00:00Z"],
                          default: nil
                        }
                      },
                      required: ["index_name_suffix", "setting_overrides"],
                      anyOf: [
                        {required: ["lt"]},
                        {required: ["lte"]},
                        {required: ["gt"]},
                        {required: ["gte"]}
                      ]
                    },
                    default: [], # : untyped
                    examples: [[{
                      "index_name_suffix" => "before_2015",
                      "lt" => "2015-01-01T00:00:00Z",
                      "setting_overrides" => {"number_of_shards" => 17}
                    }]]
                  }
                },
                required: ["query_cluster", "index_into_clusters"]
              }
            },
            examples: [{"widgets" => example_index_def}]
          },

          log_traffic: {
            type: "boolean",
            description: "Determines if we log requests/responses to/from the datastore.",
            default: false,
            examples: [false, true]
          },

          max_client_retries: {
            type: "integer",
            description: "Passed down to the datastore client. Controls the number of times ElasticGraph attempts a call against the " \
              "datastore before failing. Retrying a handful of times is generally advantageous, since some sporadic failures are expected " \
              "during the course of operation, and better to retry than fail the entire call.",
            default: 3,
            minimum: 0,
            examples: [3, 5, 10]
          }
        },
        required: ["clusters", "index_definitions"]

      private

      def convert_values(clusters:, index_definitions:, client_faraday_adapter:, **values)
        clusters = Configuration::ClusterDefinition.definitions_by_name_hash_from(clusters)
        index_definitions = Configuration::IndexDefinition.definitions_by_name_hash_from(index_definitions)
        client_faraday_adapter = Configuration::ClientFaradayAdapter.new(
          name: client_faraday_adapter.fetch("name")&.to_sym,
          require: client_faraday_adapter.fetch("require")
        )

        values.merge({
          client_faraday_adapter: client_faraday_adapter,
          clusters: clusters,
          index_definitions: index_definitions
        })
      end
    end

    module Configuration
      ClientFaradayAdapter = ::Data.define(:name, :require)
    end
  end
end
