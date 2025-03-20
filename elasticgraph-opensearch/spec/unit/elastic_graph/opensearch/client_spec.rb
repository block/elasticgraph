# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/opensearch/client"
require "elastic_graph/spec_support/datastore_client_shared_examples"

module ElasticGraph
  module OpenSearch
    RSpec.describe Client do
      it_behaves_like "a datastore client" do
        it "flattens the settings from `get_index_template` because OpenSearch appears to ignore the `flat_settings` argument" do
          client = build_client({get_index_template_my_template: {"index_templates" => [{
            "name" => "my_template",
            "index_template" => {
              "template" => {
                "mapping" => "the_mapping",
                "settings" => {"index" => {"foo" => 1, "bar" => {"bazz" => 2}}}
              },
              "index_patterns" => ["foo*"]
            }
          }]}})

          expect(client.get_index_template("my_template")).to eq({
            "index_patterns" => ["foo*"],
            "template" => {
              "settings" => {"index.foo" => 1, "index.bar.bazz" => 2},
              "mapping" => "the_mapping"
            }
          })
        end

        def define_stubs(stub, requested_stubs)
          stub.get("/") do |env|
            response_for({version: {number: "2.12.0", distribution: "opensearch"}}, env)
          end

          requested_stubs.each do |stub_name, body|
            case stub_name

            # Cluster APIs
            in :get_cluster_health
              stub.get("/_cluster/health") { |env| response_for(body, env) }
            in :get_node_os_stats
              stub.get("/_nodes/stats/os") { |env| response_for(body, env) }
            in :get_flat_cluster_settings
              stub.get("/_cluster/settings?flat_settings=true") { |env| response_for(body, env) }
            in :put_persistent_cluster_settings
              stub.put("/_cluster/settings") { |env| response_for(body, env) }

            # Script APIs
            in :get_script_123
              stub.get("/_scripts/123") { |env| response_for(body, env) }
            in :put_script_123
              stub.put("/_scripts/123/update") { |env| response_for(body, env) }
            in :delete_script_123
              stub.delete("/_scripts/123") { |env| response_for(body, env) }

            # Index Template APIs
            in :get_index_template_my_template
              stub.get("/_index_template/my_template") { |env| response_for(body, env) }
            in :put_index_template_my_template
              stub.put("/_index_template/my_template") { |env| response_for(body, env) }
            in :delete_index_template_my_template
              stub.delete("/_index_template/my_template") { |env| response_for(body, env) }

            # Index APIs
            in :get_index_my_index
              stub.get("/my_index?flat_settings=true&ignore_unavailable=true") { |env| response_for(body, env) }
            in :list_indices_matching_foo
              stub.get("/_cat/indices/foo%2A?format=json&h=index") { |env| response_for(body, env) }
            in :create_index_my_index
              stub.put("/my_index") { |env| response_for(body, env) }
            in :put_index_mapping_my_index
              stub.put("/my_index/_mappings") { |env| response_for(body, env) }
            in :put_index_settings_my_index
              stub.put("/my_index/_settings") { |env| response_for(body, env) }
            in :delete_indices_ind1_ind2
              stub.delete("/ind1,ind2?allow_no_indices=true&ignore_unavailable=true") { |env| response_for(body, env) }

            # Document APIs
            in :get_msearch
              stub.get("/_msearch") do |env|
                env.request.timeout ? raise(::Faraday::TimeoutError) : response_for(body, env)
              end
            in :post_bulk
              stub.post("/_bulk?filter_path=items.%2A.status%2Citems.%2A.result%2Citems.%2A.error&refresh=false") do |env|
                response_for(body, env)
              end
            in :delete_all_documents
              stub.post("/_all/_delete_by_query?refresh=true&scroll=10s") { |env| response_for(body, env) }
            in :delete_test_env_7_documents
              stub.post("/test_env_7_%2A/_delete_by_query?refresh=true&scroll=10s") { |env| response_for(body, env) }

            else
              # :nocov: -- none of our current tests hit this case
              raise "Unexpected stub tag: #{stub_name.inspect}"
              # :nocov:
            end
          end
        end
      end
    end
  end
end
