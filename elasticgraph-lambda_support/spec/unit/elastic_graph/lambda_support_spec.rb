# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/graphql"
require "elastic_graph/indexer"
require "elastic_graph/indexer_autoscaler_lambda"
require "elastic_graph/lambda_support"
require "elastic_graph/spec_support/lambda_function"

module ElasticGraph
  RSpec.describe LambdaSupport, ".build_from_env" do
    include_context "lambda function"

    shared_examples_for "building an ElasticGraph component" do |klass|
      around { |ex| with_lambda_env_vars(&ex) }

      it "builds an instance of the provided class" do
        instance = LambdaSupport.build_from_env(klass)

        expect(instance).to be_a klass
      end

      it "allows the caller to further customize the settings" do
        component = LambdaSupport.build_from_env(klass) do |settings|
          settings.merge("logger" => settings.fetch("logger").merge(
            "level" => "error"
          ))
        end

        expect(component.datastore_core.logger.level).to eq ::Logger::ERROR
      end

      it "sets `backend` to OpenSearch for each cluster" do
        component = LambdaSupport.build_from_env(klass)
        backend_by_cluster = component.datastore_core.config.clusters.transform_values(&:backend_client_class)

        expect(backend_by_cluster).to eq({
          "main" => OpenSearch::Client,
          "other1" => OpenSearch::Client,
          "other2" => OpenSearch::Client,
          "other3" => OpenSearch::Client
        })
      end

      it "sets the log level based on `ELASTICGRAPH_LOG_LEVEL`" do
        with_env "ELASTICGRAPH_LOG_LEVEL" => "ERROR" do
          component = LambdaSupport.build_from_env(klass)

          expect(component.datastore_core.logger.level).to eq ::Logger::ERROR
        end
      end

      it "allows `ELASTICGRAPH_LOG_LEVEL` to be unset" do
        expect(ENV["ELASTICGRAPH_LOG_LEVEL"]).to be nil

        component = LambdaSupport.build_from_env(klass)

        expect(component.datastore_core.logger.level).to eq ::Logger::INFO
      end

      it "uses our custom log formatter so we can emit JSON logs" do
        component = LambdaSupport.build_from_env(klass)

        expect(component.datastore_core.logger.formatter).to be_a(LambdaSupport::JSONAwareLambdaLogFormatter)
      end

      context "with a cluster defined in the `OPENSEARCH_CLUSTER_URLS` that is not present in the config" do
        around do |ex|
          with_lambda_env_vars(cluster_urls: {
            "main" => "main_url",
            "other1" => "other_1_url",
            "not_defined" => "not_defined_url"
          }, &ex)
        end

        it "creates a datastore ClusterDefinition for that cluster with empty settings" do
          component = LambdaSupport.build_from_env(klass)

          clusters = component.datastore_core.config.clusters
          expect(clusters.keys).to contain_exactly("main", "other1", "not_defined")
          expect(clusters["not_defined"].url).to eq("not_defined_url")
          expect(clusters["not_defined"].settings).to eq({})
        end
      end

      context "with a subset of opensearch clusters having defined urls" do
        around do |ex|
          with_lambda_env_vars(cluster_urls: {
            "main" => "main_url",
            "other1" => "other_1_url"
          }, &ex)
        end

        it "removes clusters that don't have a defined url in `OPENSEARCH_CLUSTER_URLS`." do
          component = LambdaSupport.build_from_env(klass)

          clusters = component.datastore_core.config.clusters
          expect(clusters.keys).to contain_exactly("main", "other1")
          expect(clusters["main"].url).to eq("main_url")
          expect(clusters["main"].settings).to eq({"cluster.max_shards_per_node" => 16000})
          expect(clusters["other1"].url).to eq("other_1_url")
          expect(clusters["other1"].settings).to eq({"cluster.max_shards_per_node" => 16001})
        end
      end

      it "configures the datastore faraday client" do
        allow(FaradayMiddleware::AwsSigV4).to receive(:new).and_call_original

        component = LambdaSupport.build_from_env(klass)
        component.datastore_core.clients_by_name.fetch("main")

        expect(FaradayMiddleware::AwsSigV4).to have_received(:new).at_least(:once)
      end
    end

    context "when passed `ElasticGraph::Admin`" do
      include_examples "building an ElasticGraph component", Admin
    end

    context "when passed `ElasticGraph::GraphQL`" do
      include_examples "building an ElasticGraph component", GraphQL
    end

    context "when passed `ElasticGraph::Indexer`" do
      include_examples "building an ElasticGraph component", Indexer
    end

    context "when passed `ElasticGraph::IndexerAutoscalerLambda`" do
      include_examples "building an ElasticGraph component", IndexerAutoscalerLambda
    end
  end
end
