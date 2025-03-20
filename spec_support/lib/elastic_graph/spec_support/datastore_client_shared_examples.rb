# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "httpx/adapters/faraday"
require "json"

module ElasticGraph
  RSpec.shared_examples_for "a datastore client", :no_vcr do
    it "respects the `#{TIMEOUT_MS_HEADER}` header" do
      client = build_client({get_msearch: "GET msearch"})

      expect {
        client.msearch(body: [], headers: {TIMEOUT_MS_HEADER => "1"})
      }.to raise_error Errors::RequestExceededDeadlineError, "Datastore request exceeded timeout of 1 ms."
    end

    it "converts bad request responses into `Errors::BadDatastoreRequest`" do
      client = build_client({get_cluster_health: :bad_request})

      expect {
        client.get_cluster_health
      }.to raise_error Errors::BadDatastoreRequest
    end

    describe "cluster APIs" do
      it "supports `get_cluster_health`" do
        client = build_client({get_cluster_health: {status: "healthy"}})

        expect(client.get_cluster_health).to eq({"status" => "healthy"})
      end

      it "supports `get_node_os_stats`" do
        client = build_client({get_node_os_stats: "Node stats"})

        expect(client.get_node_os_stats).to eq "Node stats"
      end

      it "supports `get_flat_cluster_settings`" do
        client = build_client({get_flat_cluster_settings: "Flat cluster settings!"})

        expect(client.get_flat_cluster_settings).to eq "Flat cluster settings!"
      end

      it "supports `put_persistent_cluster_settings`" do
        client = build_client({put_persistent_cluster_settings: :echo_body})

        expect(client.put_persistent_cluster_settings({foo: 1})).to eq({"persistent" => {"foo" => 1}})
      end
    end

    describe "script APIs" do
      it "supports `get_script`" do
        client = build_client({get_script_123: {script: "hello world"}})

        expect(client.get_script(id: "123")).to eq({"script" => "hello world"})
      end

      it "returns `nil` from `get_script` when it is not found" do
        client = build_client({get_script_123: :not_found})

        expect(client.get_script(id: "123")).to eq(nil)
      end

      it "supports `put_script`" do
        client = build_client({put_script_123: "ok"})

        expect(client.put_script(id: "123", body: "hello world", context: "update")).to eq("ok")
      end

      it "supports `delete_script`" do
        client = build_client({delete_script_123: "ok"})

        expect(client.delete_script(id: "123")).to eq("ok")
      end

      it "ignores 404s from `delete_script` since that means the script has already been deleted" do
        client = build_client({delete_script_123: :not_found})

        expect(client.delete_script(id: "123")).to eq nil
      end
    end

    describe "index template APIs" do
      it "supports `get_index_template`" do
        client = build_client({get_index_template_my_template: {"index_templates" => [{
          "name" => "my_template",
          "index_template" => {
            "template" => {
              "mapping" => "the_mapping",
              "settings" => {"foo" => "bar"}
            },
            "index_patterns" => ["foo*"]
          }
        }]}})

        expect(client.get_index_template("my_template")).to eq({
          "index_patterns" => ["foo*"],
          "template" => {
            "settings" => {"foo" => "bar"},
            "mapping" => "the_mapping"
          }
        })
      end

      it "returns `{}` from `get_index_template` when it is not found" do
        client = build_client({get_index_template_my_template: :not_found})

        expect(client.get_index_template("my_template")).to eq({})
      end

      it "supports `put_index_template`" do
        client = build_client({put_index_template_my_template: "ok"})

        expect(client.put_index_template(name: "my_template", body: {"template" => "config"})).to eq("ok")
      end

      it "supports `delete_index_template`" do
        client = build_client({delete_index_template_my_template: "ok"})

        expect(client.delete_index_template("my_template")).to eq("ok")
      end

      it "ignores 404s when deleting a template since that means its already in the desired state" do
        client = build_client({delete_index_template_my_template: :not_found})

        expect(client.delete_index_template("my_template")).to eq({})
      end
    end

    describe "index APIs" do
      it "supports `get_index`" do
        client = build_client({get_index_my_index: {"my_index" => {"settings" => "config"}}})

        expect(client.get_index("my_index")).to eq({"settings" => "config"})
      end

      it "supports `list_indices_matching`" do
        client = build_client({list_indices_matching_foo: [{"index" => "foo1"}, {"index" => "foo2"}]})

        expect(client.list_indices_matching("foo*")).to eq(["foo1", "foo2"])
      end

      it "supports `create_index`" do
        client = build_client({create_index_my_index: "ok"})

        expect(client.create_index(index: "my_index", body: {"settings" => "config"})).to eq("ok")
      end

      it "supports `put_index_mapping`" do
        client = build_client({put_index_mapping_my_index: "ok"})

        expect(client.put_index_mapping(index: "my_index", body: {"mapping" => "config"})).to eq("ok")
      end

      it "supports `put_index_settings`" do
        client = build_client({put_index_settings_my_index: "ok"})

        expect(client.put_index_settings(index: "my_index", body: {"settings" => "config"})).to eq("ok")
      end

      it "supports `delete_indices`" do
        client = build_client({delete_indices_ind1_ind2: "ok"})

        expect(client.delete_indices("ind1", "ind2")).to eq("ok")
      end
    end

    describe "document APIs" do
      it "supports `msearch`, using GET instead of POST to support simple permissioning that only allows the GraphQL endpoint to use HTTP GETs" do
        client = build_client({get_msearch: "GET msearch"})

        expect(client.msearch(body: [], headers: {})).to eq "GET msearch"
      end

      it "supports `bulk`" do
        client = build_client({post_bulk: "POST bulk"})

        expect(client.bulk(body: [])).to eq "POST bulk"
      end

      it "supports `delete_all_documents`" do
        client = build_client({delete_all_documents: "ok"})

        expect(client.delete_all_documents).to eq "ok"
      end

      it "allows an index expression to be provided to `delete_all_documents` in order to limit the deletion to documents in a specific scope" do
        client = build_client({delete_test_env_7_documents: "ok"})

        expect(client.delete_all_documents(index: "test_env_7_*")).to eq "ok"
      end
    end

    describe "the `faraday_adapter` option" do
      it "is not required" do
        expect { build_unstubbed_client }.not_to raise_error
      end

      it "allows it to be set to a valid, available adapter" do
        expect { build_unstubbed_client(faraday_adapter: :httpx) }.not_to raise_error
      end

      it "immediately raises an error if set to an unsupported value" do
        expect {
          build_unstubbed_client(faraday_adapter: :unsupported_value)
        }.to raise_error a_string_including(":unsupported_value is not registered on Faraday::Adapter")
      end

      it "immediately raises an error set to an supported but unavailable value (e.g. due to a missing gem)" do
        expect {
          build_unstubbed_client(faraday_adapter: :patron)
        }.to raise_error a_string_including(":patron is not registered on Faraday::Adapter")
      end
    end

    describe "retry behavior" do
      it "retries on a 500 (Internal Server Error) response since it's transient" do
        expect_retries_for(:internal_server_error, "500")
      end

      it "retries on a 500 (Bad Gateway) response since it's transient" do
        expect_retries_for(:bad_gateway, "502")
      end

      it "retries on a 503 (Service Unavailable) response since it's transient" do
        expect_retries_for(:service_unavailable, "503")
      end

      it "does not retry on a 504 (Gateway Timeout) response since the datastore may be overloaded and retrying could make it worse" do
        client = build_client_with_cluster_health_responses([:gateway_timeout, "ok"], retry_on_failure: 4)

        expect { client.get_cluster_health }.to raise_error a_string_including("504")
      end

      def expect_retries_for(response, expected_error)
        responses = ([response] * 5) + ["ok"]
        client = build_client_with_cluster_health_responses(responses, retry_on_failure: 4)
        expect { client.get_cluster_health }.to raise_error a_string_including(expected_error)

        client = build_client_with_cluster_health_responses(responses, retry_on_failure: 5)
        expect(client.get_cluster_health).to eq "ok"
      end

      def build_client_with_cluster_health_responses(cluster_health_responses, retry_on_failure:)
        build_client({get_cluster_health: -> { cluster_health_responses.shift }}, retry_on_failure: retry_on_failure)
      end
    end

    describe "logging", :capture_logs, :expect_warning_logging do
      it "logs full traffic details when provided with a `logger`" do
        build_client({put_persistent_cluster_settings: "ok"}, logger: logger).put_persistent_cluster_settings({
          "indices.recovery.max_bytes_per_sec" => "50mb"
        })

        # Verify that we include both basic log details and trace details.
        expect(logged_output.lines).to include(
          a_string_including("INFO -- : PUT http://ignoredhost.com:9200/_cluster/settings"),
          a_string_including("INFO -- : curl -X PUT", "/_cluster/settings"),
          a_string_including("indices.recovery.max_bytes_per_sec", "50mb")
        )
      end

      it "does not log traffic when no `logger` is provided" do
        build_client({put_persistent_cluster_settings: "ok"}, logger: nil).put_persistent_cluster_settings({
          "indices.recovery.max_bytes_per_sec" => "50mb"
        })

        expect(logged_output).to be_empty
      end
    end

    def build_client(stubs_by_name, **options)
      described_class.new(
        "some-cluster",
        faraday_adapter: :test,
        url: "http://ignoredhost.com",
        **options
      ) do |faraday|
        faraday.adapter :test do |stub|
          define_stubs(stub, stubs_by_name)
        end
      end
    end

    def build_unstubbed_client(**options)
      described_class.new("some-cluster", url: "http://ignoredhost.com", **options)
    end

    def response_for(body, env)
      status, headers, body =
        case body
        in :echo_body
          [200, {"Content-Type" => "application/json"}, env.body]
        in :internal_server_error
          [500, {"Content-Type" => "application/json"}, "{}"]
        in :bad_gateway
          [502, {"Content-Type" => "application/json"}, "{}"]
        in :service_unavailable
          [503, {"Content-Type" => "application/json"}, "{}"]
        in :gateway_timeout
          [504, {"Content-Type" => "application/json"}, "{}"]
        in :not_found
          [404, {"Content-Type" => "application/json"}, "{}"]
        in :bad_request
          [400, {"Content-Type" => "application/json"}, "{}"]
        in ::String
          [200, {"Content-Type" => "text/plain"}, body]
        in ::Proc
          response_for(body.call, env)
        else
          [200, {"Content-Type" => "application/json"}, ::JSON.generate(body)]
        end

      # Here we rewrap the body in a new string, because the datastore client attempts to mutate
      # the encoding of the body, and when we run on CI with "--enable-frozen-string-literal" we
      # get errors if we haven't wrapped it in a new string instance.
      [status, headers, ::String.new(body)]
    end
  end
end
