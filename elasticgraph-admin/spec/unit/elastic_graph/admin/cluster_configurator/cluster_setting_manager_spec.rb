# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin"
require "elastic_graph/admin/cluster_configurator/cluster_settings_manager"

module ElasticGraph
  class Admin
    class ClusterConfigurator
      RSpec.describe ClusterSettingsManager, :stub_datastore_client do
        let(:main_datastore_client) { new_datastore_client("main") }
        let(:other1_datastore_client) { new_datastore_client("other1") }
        let(:other2_datastore_client) { new_datastore_client("other2") }
        let(:admin) { build_admin_with_stubbed_datastore_clients }

        describe "#start_index_maintenance_mode!" do
          it "disables auto index creation on the named cluster" do
            admin.cluster_settings_manager.start_index_maintenance_mode!("other1")

            expect(main_datastore_client).to have_left_cluster_auto_create_index_setting_unchanged
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*")
          end

          it "disables auto index creation on all clusters when passed `:all_clusters`" do
            admin.cluster_settings_manager.start_index_maintenance_mode!(:all_clusters)

            expect(main_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*")
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*")
            expect(other2_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*")
          end
        end

        describe "#end_index_maintenance_mode!" do
          it "enables auto index creation on the named cluster" do
            admin.cluster_settings_manager.end_index_maintenance_mode!("other1")

            expect(main_datastore_client).to have_left_cluster_auto_create_index_setting_unchanged
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*")
          end

          it "enables auto index creation on all clusters when passed `:all_clusters`" do
            admin.cluster_settings_manager.end_index_maintenance_mode!(:all_clusters)

            expect(main_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*")
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*")
            expect(other2_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*")
          end
        end

        describe "#in_index_maintenance_mode", :capture_logs do
          it "runs the block while auto index creation is disabled on the named cluster, re-enabling it afterward" do
            admin.cluster_settings_manager.in_index_maintenance_mode("other1") do
            end

            expect(main_datastore_client).to have_left_cluster_auto_create_index_setting_unchanged
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*").ordered
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*").ordered
          end

          it "leaves maintenance mode enabled if an exception occurs in the block, to guard against indices being created with the wrong settings" do
            expect {
              admin.cluster_settings_manager.in_index_maintenance_mode("other1") do
                raise "boom"
              end
            }.to raise_error("boom").and log_warning(a_string_including("in_index_maintenance_mode is not able to exit index maintenance mode"))

            expect(main_datastore_client).to have_left_cluster_auto_create_index_setting_unchanged
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*").ordered
            expect(other1_datastore_client).not_to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*")
          end

          it "applies to all clusters when given `:all_clusters`" do
            admin.cluster_settings_manager.in_index_maintenance_mode(:all_clusters) do
            end

            expect(main_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*").ordered
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*").ordered
            expect(other2_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*").ordered

            expect(main_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*").ordered
            expect(other1_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*").ordered
            expect(other2_datastore_client).to change_cluster_auto_create_index_setting_to("+.kibana*", "+*_rollover__*").ordered
          end
        end

        it "raises a clear error when given an unknown cluster name" do
          expect {
            admin.cluster_settings_manager.start_index_maintenance_mode!("unknown")
          }.to raise_error Errors::ClusterOperationError, a_string_including("unknown", "main", "other1", "other2")

          expect {
            admin.cluster_settings_manager.end_index_maintenance_mode!("unknown")
          }.to raise_error Errors::ClusterOperationError, a_string_including("unknown", "main", "other1", "other2")

          expect {
            admin.cluster_settings_manager.in_index_maintenance_mode("unknown") do
            end
          }.to raise_error Errors::ClusterOperationError, a_string_including("unknown", "main", "other1", "other2")
        end

        it "favors cluster settings in app configuration over defaults" do
          cluster_setting_overrides = {
            "indices.recovery.max_concurrent_operations" => 2, # new setting
            "search.allow_expensive_queries" => false # setting override
          }

          admin = build_admin_with_stubbed_datastore_clients do |config|
            config.with(clusters: config.clusters.merge(
              "other1" => config.clusters.fetch("main").with(settings: cluster_setting_overrides)
            ))
          end

          admin.cluster_settings_manager.end_index_maintenance_mode!("main")
          expect(main_datastore_client).to have_received(:put_persistent_cluster_settings).with(
            a_hash_excluding("indices.recovery.max_concurrent_operations")
          )

          admin.cluster_settings_manager.end_index_maintenance_mode!("other1")
          expect(other1_datastore_client).to have_received(:put_persistent_cluster_settings).with(
            a_hash_including("indices.recovery.max_concurrent_operations" => 2, "search.allow_expensive_queries" => false)
          )
        end

        def build_admin_with_stubbed_datastore_clients(**options, &block)
          build_admin(clients_by_name: {
            "main" => main_datastore_client,
            "other1" => other1_datastore_client,
            "other2" => other2_datastore_client
          }, **options, &block)
        end

        def new_datastore_client(name)
          instance_double("ElasticGraph::Elasticsearch::Client", name, get_flat_cluster_settings: {"persistent" => {}}, put_persistent_cluster_settings: nil)
        end

        def have_left_cluster_auto_create_index_setting_unchanged
          have_never_received(:put_persistent_cluster_settings)
        end

        def change_cluster_auto_create_index_setting_to(*expressions)
          have_received(:put_persistent_cluster_settings).with(a_hash_including("action.auto_create_index" => expressions.join(",")))
        end
      end
    end
  end
end
