# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/datastore_response/search_response"
require "elastic_graph/health_check/health_checker"
require "elastic_graph/support/hash_util"

module ElasticGraph
  module HealthCheck
    RSpec.describe HealthChecker, :capture_logs, :builds_graphql do
      let(:cluster_names) { ["main", "other1", "other2"] }
      let(:now) { ::Time.iso8601("2022-02-14T12:30:00Z") }
      let(:datastore_query_body_by_type) { {} }

      attr_reader :example_datastore_health_response

      before(:context) do
        @example_datastore_health_response = {
          # Note: we intentionally have a different value for every field here, so that
          # our assertions below can demonstrate that the returned values come from the
          # datastore response fields.
          "cluster_name" => "replace_me",
          "status" => "yellow",
          "timed_out" => false,
          "number_of_nodes" => 1,
          "number_of_data_nodes" => 2,
          "active_primary_shards" => 3,
          "active_shards" => 4,
          "relocating_shards" => 5,
          "initializing_shards" => 6,
          "unassigned_shards" => 7,
          "delayed_unassigned_shards" => 8,
          "number_of_pending_tasks" => 9,
          "number_of_in_flight_fetch" => 10,
          "task_max_waiting_in_queue_millis" => 11,
          "active_shards_percent_as_number" => 50.0,
          "discovered_master" => true
        }

        expect(@example_datastore_health_response.keys).to match_array(DATASTORE_CLUSTER_HEALTH_FIELDS.map(&:to_s))
      end

      describe "with valid configuration" do
        let(:valid_config) do
          Config.new(
            clusters_to_consider: ["main", "other1"],
            data_recency_checks: {
              "Widget" => build_recency_check(timestamp_field: "created_at", expected_max_recency_seconds: 30),
              "Component" => build_recency_check(timestamp_field: "created_at", expected_max_recency_seconds: 30)
            }
          )
        end

        it "queries and returns the cluster health information" do
          status = build_health_checker(health_check: valid_config).check_health

          expect(status.cluster_health_by_name.keys).to contain_exactly("main", "other1")

          expect(status.cluster_health_by_name["main"]).to eq HealthStatus::ClusterHealth.new(
            **Support::HashUtil.symbolize_keys(example_datastore_health_response).merge(
              cluster_name: "main"
            )
          )

          expect(status.cluster_health_by_name["other1"]).to eq HealthStatus::ClusterHealth.new(
            **Support::HashUtil.symbolize_keys(example_datastore_health_response).merge(
              cluster_name: "other1"
            )
          )
        end

        it "ignores extra health status fields returned by the datastore" do
          status = build_health_checker(health_check: valid_config) do |health_response|
            health_response.merge("extra_field" => "23")
          end.check_health

          expect(status.cluster_health_by_name.keys).to contain_exactly("main", "other1")

          expect(status.cluster_health_by_name["main"]).to eq HealthStatus::ClusterHealth.new(
            **Support::HashUtil.symbolize_keys(example_datastore_health_response).merge(
              cluster_name: "main"
            )
          )

          expect(status.cluster_health_by_name["other1"]).to eq HealthStatus::ClusterHealth.new(
            **Support::HashUtil.symbolize_keys(example_datastore_health_response).merge(
              cluster_name: "other1"
            )
          )
        end

        it "does not fail when the datastore health status response does not include one of our defined fields" do
          status = build_health_checker(health_check: valid_config) do |health_response|
            health_response.except("number_of_nodes")
          end.check_health

          expect(status.cluster_health_by_name.keys).to contain_exactly("main", "other1")

          expect(status.cluster_health_by_name["main"]).to eq HealthStatus::ClusterHealth.new(
            **Support::HashUtil.symbolize_keys(example_datastore_health_response).merge(
              cluster_name: "main",
              number_of_nodes: nil
            )
          )

          expect(status.cluster_health_by_name["other1"]).to eq HealthStatus::ClusterHealth.new(
            **Support::HashUtil.symbolize_keys(example_datastore_health_response).merge(
              cluster_name: "other1",
              number_of_nodes: nil
            )
          )
        end

        it "queries and returns the latest record info for the configured data recency checks" do
          status = build_health_checker(
            health_check: valid_config,
            latest: {
              "Widget" => {"id" => "w1", "created_at" => (now - 100).iso8601},
              "Component" => {"id" => "c1", "created_at" => (now - 50).iso8601}
            }
          ).check_health

          expect(status.latest_record_by_type.keys).to contain_exactly("Widget", "Component")

          expect(status.latest_record_by_type["Widget"]).to eq HealthStatus::LatestRecord.new(
            id: "w1",
            timestamp: now - 100,
            seconds_newer_than_required: -70 # 30 - 100
          )

          expect(status.latest_record_by_type["Component"]).to eq HealthStatus::LatestRecord.new(
            id: "c1",
            timestamp: now - 50,
            seconds_newer_than_required: -20 # 30 - 50
          )
        end

        it "returns `nil` for a type's latest record if there is no data in that type's index" do
          status = build_health_checker(
            health_check: valid_config,
            latest: {}
          ).check_health

          expect(status.latest_record_by_type).to eq("Widget" => nil, "Component" => nil)
        end

        it "only ever asks for one record" do
          build_health_checker(health_check: valid_config).check_health

          # Note: while we build the query to only ask for 1, the current implementation of DatastoreQuery
          # will ask for one more in order to implement `has_previous_page`/`has_next_page`. There's an
          # unimplemented optimization to not ask for one more when the client hasn't asked for those fields.
          # Here we want to tolerate that optimization being present or not so we allow the size to be 1 or 2.
          expect(datastore_query_body_by_type.fetch("Widget")["size"]).to eq(1).or eq(2)
          expect(datastore_query_body_by_type.fetch("Component")["size"]).to eq(1).or eq(2)
        end

        it "sorts by the timestamp field descending in order to get the latest record" do
          build_health_checker(health_check: valid_config).check_health

          expect(datastore_query_body_by_type.fetch("Widget")["sort"]).to start_with("created_at" => a_hash_including({"order" => "desc"}))
          expect(datastore_query_body_by_type.fetch("Component")["sort"]).to start_with("created_at" => a_hash_including({"order" => "desc"}))
        end

        it "only requests the timestamp field for optimal queries" do
          build_health_checker(health_check: valid_config).check_health

          expect(datastore_query_body_by_type.fetch("Widget")["_source"]).to eq("includes" => ["created_at"])
          expect(datastore_query_body_by_type.fetch("Component")["_source"]).to eq("includes" => ["created_at"])
        end

        it "filters by the timestamp field on all types regardless of whether it is a rollover index or not, to optimize the query" do
          build_health_checker(health_check: valid_config).check_health

          expect(datastore_query_body_by_type.fetch("Widget")["query"]).to match({
            "bool" => {"filter" => [
              {"range" => {"created_at" => {"gte" => a_value < (now - 100).iso8601}}}
            ]}
          })

          expect(datastore_query_body_by_type.fetch("Component")["query"]).to match({
            "bool" => {"filter" => [
              {"range" => {"created_at" => {"gte" => a_value < (now - 100).iso8601}}}
            ]}
          })
        end

        context "when a configured `timestamp_field` has a different `name_in_index`" do
          it "correctly uses the `name_in_index` for all index field references" do
            config = valid_config.with(data_recency_checks: {
              # created_at2 is defined in config/schema.rb with `name_in_index: "created_at"
              "Widget" => build_recency_check(timestamp_field: "created_at2")
            })

            status = build_health_checker(
              health_check: config,
              latest: {"Widget" => {"id" => "w1", "created_at" => (now - 100).iso8601}}
            ).check_health

            expect(status.latest_record_by_type).to eq("Widget" => HealthStatus::LatestRecord.new(
              id: "w1",
              timestamp: now - 100,
              seconds_newer_than_required: -70 # 30 - 100
            ))

            query_body = datastore_query_body_by_type.fetch("Widget")
            expect(query_body["sort"]).to start_with("created_at" => a_hash_including({"order" => "desc"}))
            expect(query_body["_source"]).to eq("includes" => ["created_at"])
            expect(query_body["query"]).to match({
              "bool" => {"filter" => [
                {"range" => {"created_at" => {"gte" => a_value < (now - 100).iso8601}}}
              ]}
            })
          end
        end
      end

      describe "config validation" do
        it "raises a clear error when instantiated with a `clusters_to_consider` option referencing a cluster that does not exist" do
          expect {
            build_health_checker(health_check: Config.new(
              clusters_to_consider: ["main", "other2", "other3", "other4"],
              data_recency_checks: {}
            ))
          }.to raise_error Errors::ConfigError, a_string_including(
            "clusters_to_consider",
            "unrecognized cluster names",
            "other3", "other4"
          ).and(excluding("main", "other2"))
        end

        context "with subset of clusters available for querying" do
          let(:cluster_names) { ["other2"] }

          # The situation here is that only "other2" is an accessible cluster. The healthcheck is configured to check "main". The
          # Widget type references "main" as an "query" cluster - health_checker should not claim "main" is unrecognized.
          it "uses query clusters on indexing definitions for recognizing clusters" do
            expect {
              health_checker = build_health_checker(
                health_check: Config.new(
                  clusters_to_consider: ["main"],
                  data_recency_checks: {
                    "Widget" => build_recency_check(timestamp_field: "created_at")
                  }
                ),
                index_definitions: {
                  "widgets" => config_index_def_of(query_cluster: "main", index_into_clusters: ["other3"])
                },
                schema_definition: lambda do |schema|
                  schema.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.field "created_at", "DateTime!"
                    t.index "widgets" do |i|
                      i.default_sort "created_at", :desc
                    end
                  end
                end
              )

              status = health_checker.check_health
              expect(status.cluster_health_by_name.keys).to be_empty # Can't check cluster health, as "main" not available
              expect(status.latest_record_by_type.keys).to be_empty # .. and can't do recency check, as `widgets` relies on main.
            }.to log_warning a_string_including("1 type(s) were unavailable for health-checking", "Widget",
              "1 cluster(s) were unavailable for health-checking", "main")
          end

          # The state here is only "other2" is an accessible cluster. The cluster health check is configured to check "main". The
          # Widget type references "main" as an "index_into" cluster - health_checker should not claim "main" is unrecognized.
          it "uses index_into clusters on indexing definitions for recognizing clusters" do
            expect {
              health_checker = build_health_checker(
                health_check: Config.new(
                  clusters_to_consider: ["main"],
                  data_recency_checks: {
                    "Widget" => build_recency_check(timestamp_field: "created_at")
                  }
                ),
                index_definitions: {
                  "widgets" => config_index_def_of(query_cluster: "other3", index_into_clusters: ["main"])
                },
                schema_definition: lambda do |schema|
                  schema.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.field "created_at", "DateTime!"
                    t.index "widgets" do |i|
                      i.default_sort "created_at", :desc
                    end
                  end
                end
              )

              status = health_checker.check_health
              expect(status.cluster_health_by_name.keys).to be_empty # Can't check cluster health, as "main" not available
              expect(status.latest_record_by_type.keys).to be_empty # .. and can't do recency check, as `widgets` relies on `other3`, which is not available.
            }.to log_warning a_string_including("1 type(s) were unavailable for health-checking", "Widget",
              "1 cluster(s) were unavailable for health-checking", "main")
          end

          it "ignores datastore health checks for clusters not available for querying" do
            expect {
              health_checker = build_health_checker(
                health_check: Config.new(
                  clusters_to_consider: ["main", "other2"], # "main" is not available, only other2 is available.
                  data_recency_checks: {}
                )
              )

              status = health_checker.check_health
              expect(status.latest_record_by_type.keys).to be_empty # No recency checks.
              expect(status.cluster_health_by_name.keys).to contain_exactly("other2") # Just "other2", not "main"
            }.to log_warning a_string_including("1 cluster(s) were unavailable for health-checking", "main")
          end

          it "ignores recency health checks for types whose query clusters are not available for querying" do
            # The state here is that the "Widget" type is backed by the "widgets" index, which depends on the "main" datastore cluster for querying.
            # However, the graphql endpoint only has access to the "other2" cluster (see the `cluster_names` override above). So the recency health check
            # for "Widget" should be skipped, but a warning should be logged.
            #
            # Separately, there is the "Component" type - which is backed by the "other2" cluster for queries - because that is available, it *should* be type-checked.
            expect {
              health_checker = build_health_checker(
                health_check: Config.new(
                  clusters_to_consider: [],
                  data_recency_checks: {
                    "Widget" => build_recency_check(timestamp_field: "created_at"),
                    "Component" => build_recency_check(timestamp_field: "created_at")
                  }
                ),
                index_definitions: {
                  # The "query" cluster should be used for determining recency health check eligibility, not the indexing clusters. So to check that, only "other2" is made available,
                  # and so only the Component health check should be used.
                  "widgets" => config_index_def_of(query_cluster: "main", index_into_clusters: ["other2"]),
                  "components" => config_index_def_of(query_cluster: "other2", index_into_clusters: ["other2"])
                },
                schema_definition: lambda do |schema|
                  schema.object_type "Widget" do |t|
                    t.field "id", "ID!"
                    t.field "created_at", "DateTime!"
                    t.index "widgets" do |i|
                      i.default_sort "created_at", :desc
                    end
                  end

                  schema.object_type "Component" do |t|
                    t.field "id", "ID!"
                    t.field "created_at", "DateTime!"
                    t.index "components" do |i|
                      i.default_sort "created_at", :desc
                    end
                  end
                end
              )

              status = health_checker.check_health
              expect(status.latest_record_by_type.keys).to contain_exactly("Component") # Widget should not be present, since its query datastore clusters can be accessed.
            }.to log_warning a_string_including("1 type(s) were unavailable for health-checking", "Widget")
          end
        end

        it "raises a clear error when instantiated with `data_recency_checks` that name unknown types" do
          expect {
            build_health_checker(health_check: Config.new(
              clusters_to_consider: ["main"],
              data_recency_checks: {
                "UnknownType1" => build_recency_check,
                "UnknownType2" => build_recency_check,
                "Widget" => build_recency_check
              }
            ))
          }.to raise_error Errors::ConfigError, a_string_including(
            "data_recency_checks",
            "not recognized indexed types",
            "UnknownType1", "UnknownType2"
          ).and(excluding("Widget"))
        end

        it "raises a clear error when instantiated with `data_recency_checks` that name types that are not indexed" do
          expect {
            build_health_checker(health_check: Config.new(
              clusters_to_consider: ["main"],
              data_recency_checks: {
                "Component" => build_recency_check,
                # Color is an enum type
                "Color" => build_recency_check,
                # DateTime is a scalar type
                "DateTime" => build_recency_check,
                # WidgetOptions is an embedded object type
                "WidgetOptions" => build_recency_check
              }
            ))
          }.to raise_error Errors::ConfigError, a_string_including(
            "data_recency_checks",
            "not recognized indexed types",
            "Color", "DateTime", "WidgetOptions"
          ).and(excluding("Component"))
        end

        it "raises a clear error when instantiated with a data recency check timestamp field that does not exist" do
          expect {
            build_health_checker(health_check: Config.new(
              clusters_to_consider: ["main"],
              data_recency_checks: {
                "Widget" => build_recency_check(timestamp_field: "created_at"),
                "Component" => build_recency_check(timestamp_field: "generated_at")
              }
            ))
          }.to raise_error Errors::ConfigError, a_string_including(
            "data_recency_checks",
            "invalid timestamp fields",
            "Component", "generated_at"
          ).and(excluding("Widget", "created_at"))
        end

        it "raises a clear error when instantiated with a data recency check timestamp field that does not exist" do
          expect {
            build_health_checker(health_check: Config.new(
              clusters_to_consider: ["main"],
              data_recency_checks: {
                "Widget" => build_recency_check(timestamp_field: "created_at"),
                "Component" => build_recency_check(timestamp_field: "name")
              }
            ))
          }.to raise_error Errors::ConfigError, a_string_including(
            "data_recency_checks",
            "invalid timestamp fields",
            "Component", "name"
          ).and(excluding("Widget", "created_at"))
        end
      end

      def build_health_checker(health_check:, latest: {}, index_definitions: nil, schema_definition: nil, &customize_health)
        datastore_clients_by_name = cluster_names.to_h do |name|
          [name, build_fake_datastore_client(name, latest, &customize_health)]
        end

        health_check_settings = Support::HashUtil.stringify_keys(health_check.to_h.merge(
          data_recency_checks: health_check.data_recency_checks.transform_values(&:to_h)
        ))

        graphql = build_graphql(
          clients_by_name: datastore_clients_by_name,
          clock: class_double(::Time, now: now),
          schema_definition: schema_definition,
          index_definitions: index_definitions,
          extension_settings: {"health_check" => health_check_settings}
        )

        HealthChecker.build_from(graphql)
      end

      def build_fake_datastore_client(name, latest_records_by_type, &customize_health)
        cluster_health = example_datastore_health_response.merge("cluster_name" => name)
        cluster_health = customize_health.call(cluster_health) if customize_health

        stubbed_datastore_client(get_cluster_health: cluster_health).tap do |client|
          allow(client).to receive(:msearch) do |request|
            build_msearch_response(request, latest_records_by_type)
          end
        end
      end

      def build_msearch_response(request, latest_record_by_type)
        # Our query logic generates a payload with a mixture of string and symbol keys
        # (it doesn't matter to the datastore since it serializes in JSON the same).
        # Here we do not want to be mix and match (or be coupled to the current key form
        # being used) so we normalize to string keys here.
        normalized_request = Support::HashUtil.stringify_keys(request)

        responses = normalized_request.fetch("body").each_slice(2).map do |(headers, body)|
          type =
            case headers.fetch("index")
            when /widget/ then "Widget"
            when /component/ then "Component"
            # :nocov: -- this `else` case is only hit when tests here have bugs
            else raise "Unknown index: #{headers.fetch("index")}"
              # :nocov:
            end

          datastore_query_body_by_type[type] = body

          if (latest_values = latest_record_by_type[type])
            Support::HashUtil.deep_merge(
              GraphQL::DatastoreResponse::SearchResponse::RAW_EMPTY,
              {"hits" => {"hits" => [{"_id" => latest_values.fetch("id"), "_source" => latest_values}]}}
            )
          else
            GraphQL::DatastoreResponse::SearchResponse::RAW_EMPTY
          end
        end

        {"responses" => responses}
      end

      def build_recency_check(expected_max_recency_seconds: 30, timestamp_field: "created_at")
        Config::DataRecencyCheck.new(
          expected_max_recency_seconds: expected_max_recency_seconds,
          timestamp_field: timestamp_field
        )
      end
    end
  end
end
