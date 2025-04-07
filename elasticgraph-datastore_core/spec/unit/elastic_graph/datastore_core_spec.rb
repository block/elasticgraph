# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core"
require "elastic_graph/datastore_core/config"
require "elastic_graph/elasticsearch/client"
require "logger"

module ElasticGraph
  # stub_datastore_client - the specs below depend on using a real datastore client (but don't send any
  #                       requests to the datastore, so they are stll unit tests).
  RSpec.describe DatastoreCore, stub_datastore_client: false do
    it "returns non-nil values from each attribute" do
      expect_to_return_non_nil_values_from_all_attributes(build_datastore_core(
        # Give `client_customization_block` a non-nil value for this test...
        client_customization_block: ->(client) { client }
      ))
    end

    describe ".from_parsed_yaml" do
      it "can build an instance from a parsed settings YAML file" do
        datastore_core = DatastoreCore.from_parsed_yaml(parsed_test_settings_yaml)

        expect(datastore_core).to be_an(DatastoreCore)
      end

      it "allows the datastore clients to be customized via the passed block" do
        customization_block = lambda { |conn| }
        datastore_core = DatastoreCore.from_parsed_yaml(parsed_test_settings_yaml, &customization_block)

        expect(datastore_core.client_customization_block).to be(customization_block)
      end
    end

    context "when built for our tests" do
      it "overrides settings on every index for optimal test speed (intentionally giving up data durability)" do
        datastore_core = build_datastore_core
        index_def_names = datastore_core.schema_artifacts.index_mappings_by_index_def_name.keys

        settings_for_each_index = index_def_names.map do |index_name|
          datastore_core.config.index_definitions[index_name].setting_overrides
        end

        expect(settings_for_each_index).to all include("translog.durability" => "async")
      end
    end

    it "builds the client with a logger when `config.log_traffic` is true" do
      client_class = class_spy(Elasticsearch::Client).as_stubbed_const
      build_datastore_core(log_traffic: true, datastore_backend: :elasticsearch).clients_by_name

      expect(client_class).to have_received(:new)
        .with(an_instance_of(::String), hash_including(logger: an_object_responding_to(:info, :warn, :error)))
        .at_least(:once)
    end

    it "builds the client without a logger when `config.log_traffic` is false" do
      client_class = class_spy(Elasticsearch::Client).as_stubbed_const
      build_datastore_core(log_traffic: false, datastore_backend: :elasticsearch).clients_by_name

      expect(client_class).to have_received(:new)
        .with(an_instance_of(::String), hash_including(logger: nil))
        .at_least(:once)
    end

    it "allows `client_customization_block` to be injected, to support `elasticgraph-lambda` using an AWS signing client" do
      expect { |probe|
        build_datastore_core(
          client_customization_block: probe
        ) do |config|
          # Ensure only one cluster is configured so `datastore_client_customization_block` is only used once.
          config.with(clusters: config.clusters.first(1).to_h)
        end.clients_by_name
      }.to yield_with_args an_object_satisfying { |f| f.is_a?(::Faraday::Connection) }
    end

    def build_datastore_core(client_faraday_adapter: nil, **options)
      client_faraday_adapter &&= DatastoreCore::Configuration::ClientFaradayAdapter.new(
        name: client_faraday_adapter.to_sym,
        require: nil
      )

      super(client_faraday_adapter: client_faraday_adapter, **options)
    end
  end
end
