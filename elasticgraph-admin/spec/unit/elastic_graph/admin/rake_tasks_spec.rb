# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/rake_tasks"

module ElasticGraph
  class Admin
    RSpec.describe RakeTasks, :rake_task do
      let(:main_datastore_client) { stubbed_datastore_client }
      let(:other_datastore_client) { stubbed_datastore_client }

      it "evaluates the admin load block lazily so that if loading fails it only interferes with running tasks, not defining them" do
        # Simulate schema artifacts being out of date.
        load_admin = lambda { raise "schema artifacts are out of date" }

        # Printing tasks is unaffected...
        output = run_rake("--tasks", &load_admin)
        expect(output).to eq(<<~EOS)
          rake clusters:configure:dry_run                 # Dry-runs the configuration of datastore clusters, including indices, settings, and scripts
          rake clusters:configure:perform                 # Performs the configuration of datastore clusters, including indices, settings, and scripts
          rake indices:drop[index_def_name,cluster_name]  # Drops the specified index definition on the specified datastore cluster
          rake indices:drop_prototypes                    # Drops all prototype index definitions on all datastore clusters
        EOS

        # ...but when you run a task that needs the `Admin` instance the failure is surfaced.
        expect {
          run_rake("clusters:configure:dry_run", &load_admin)
        }.to raise_error "schema artifacts are out of date"
      end

      describe "indices:drop_prototypes" do
        it "puts cluster in index maintenance mode, then drops all index definitions named in `prototype_index_names` but none others" do
          admin = admin_with_schema do |schema|
            schema.object_type "Widget1" do |t|
              t.field "id", "ID!"
              t.index "widgets1"
            end

            schema.object_type "Widget2" do |t|
              t.field "id", "ID!"
              t.index "widgets2"
            end

            schema.object_type "Widget3" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime!"
              t.index "widgets3" do |i|
                i.rollover :monthly, "created_at"
              end
            end

            schema.object_type "Widget4" do |t|
              t.field "id", "ID!"
              t.field "created_at", "DateTime!"
              t.index "widgets4" do |i|
                i.rollover :monthly, "created_at"
              end
            end
          end

          # While we generally try to avoid mocking in the ElasticGraph test suite, here we are doing it because
          # if we let the test delete indices for real, it deletes the index configuration that many other tests
          # rely on. We could recreate that, but it's pretty slow (takes ~2 seconds) and the value of tests that
          # cover this task are relatively low given this task is only ever run by an engineer as an admin
          # task and this code is never in the path for a client request.
          #
          # So we have opted to mock it, as the "least bad" way of testing this.
          call_order = []
          expect(admin.cluster_settings_manager).to receive(:start_index_maintenance_mode!) { |arg| call_order << [:start_index_maintenance_mode!, arg] }
          expect(main_datastore_client).to receive(:delete_index_template).with("widgets4") { call_order << :delete_template }
          expect(main_datastore_client).to receive(:delete_indices).with("widgets2") { call_order << :delete }
          expect(other_datastore_client).to receive(:delete_index_template).with("widgets4") { call_order << :delete_template }
          expect(other_datastore_client).to receive(:delete_indices).with("widgets2") { call_order << :delete }

          expect(main_datastore_client).not_to receive(:delete_index_template).with("widgets3")
          expect(main_datastore_client).not_to receive(:delete_indices).with("widgets1")
          expect(other_datastore_client).not_to receive(:delete_index_template).with("widgets3")
          expect(other_datastore_client).not_to receive(:delete_indices).with("widgets1")

          output = run_rake("indices:drop_prototypes", prototype_index_names: ["widgets2", "widgets4"]) { admin }

          expect(output.lines).to include(a_string_including("Disabled rollover index auto creation for all clusters"))
          expect(output.lines).to include(a_string_including("Dropping the following prototype index definitions", "widgets2", "widgets4"))
          expect(output.lines).to include(a_string_including("Finished dropping all prototype index definitions"))

          expect(call_order).to start_with([:start_index_maintenance_mode!, :all_clusters])
        end

        it "ignores indices that do not reside on an accessible datastore cluster" do
          admin = admin_with_schema(
            clusters: {"main" => cluster_of},
            index_definitions: {
              "widgets1" => config_index_def_of(query_cluster: "main", index_into_clusters: ["main", "other"]),
              "widgets2" => config_index_def_of(query_cluster: "other", index_into_clusters: ["other"])
            }
          ) do |schema|
            schema.object_type "Widget1" do |t|
              t.field "id", "ID!"
              t.index "widgets1"
            end

            schema.object_type "Widget2" do |t|
              t.field "id", "ID!"
              t.index "widgets2"
            end
          end

          allow(admin.cluster_settings_manager).to receive(:start_index_maintenance_mode!)
          expect(main_datastore_client).to receive(:delete_indices)
          expect(other_datastore_client).not_to receive(:delete_indices)

          output = run_rake("indices:drop_prototypes", prototype_index_names: ["widgets1", "widgets2"]) { admin }

          expect(output.lines).to include(a_string_including("Dropping the following prototype index definitions", "widgets1").and(excluding("widgets2")))
        end
      end

      describe "indices:drop" do
        it "does not drop the index if it is not listed in `prototype_index_names`" do
          admin = admin_with_widgets

          expect(admin.cluster_settings_manager).not_to receive(:start_index_maintenance_mode!)
          expect(main_datastore_client).not_to receive(:delete_indices).with("*")
          expect(other_datastore_client).not_to receive(:delete_indices).with("*")
          expect(admin.cluster_settings_manager).not_to receive(:end_index_maintenance_mode!)

          expect {
            run_rake("indices:drop[widgets, other]", prototype_index_names: ["components"]) { admin }
          }.to raise_error(Errors::IndexOperationError, a_string_including("widgets", "live index", "prototype_index_names"))
        end

        it "drops the index on the specified datastore cluster if it is listed in `prototype_index_names`" do
          admin = admin_with_widgets

          expect(admin.cluster_settings_manager).to receive(:start_index_maintenance_mode!).with("other").ordered
          expect(main_datastore_client).not_to receive(:delete_indices).with("widgets")
          expect(other_datastore_client).to receive(:delete_indices).with("widgets").ordered
          expect(admin.cluster_settings_manager).to receive(:end_index_maintenance_mode!).with("other").ordered

          output = run_rake("indices:drop[widgets, other]", prototype_index_names: ["widgets"]) { admin }
          expect(output.lines).to include(a_string_including("Disabled rollover index auto creation for this cluster"))
          expect(output.lines).to include(a_string_including("Dropped index"))
        end

        it "fails with a clear error if the specified cluster does not exist" do
          admin = admin_with_widgets

          expect {
            run_rake("indices:drop[widgets, typo]", prototype_index_names: ["widgets"]) { admin }
          }.to raise_error Errors::IndexOperationError, a_string_including('Cluster named `typo` does not exist. Valid clusters: ["main", "other"]')
        end
      end

      def admin_with_schema(
        clusters: {"main" => cluster_of, "other" => cluster_of},
        index_definitions: Hash.new do |h, k|
          h[k] = config_index_def_of(query_cluster: "main", index_into_clusters: ["main", "other"])
        end,
        &schema_definition
      )
        build_admin(
          schema_definition: schema_definition,
          clients_by_name: {"main" => main_datastore_client, "other" => other_datastore_client}
        ) do |config|
          config.with(
            clusters: clusters,
            index_definitions: index_definitions
          )
        end
      end

      def admin_with_widgets
        admin_with_schema do |schema|
          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.index "widgets"
          end
        end
      end

      def run_rake(*args, prototype_index_names: [], &load_admin)
        super(*args) do |output|
          RakeTasks.new(prototype_index_names: prototype_index_names, output: output, &load_admin)
        end
      end
    end

    # This is a separate example group because it needs `run_rake` to be defined differently from the group above.
    RSpec.describe RakeTasks, ".from_yaml_file", :rake_task do
      it "loads the admin instance from the given yaml file" do
        output = run_rake "--tasks"

        expect(output).to include("rake clusters")
      end

      def run_rake(*args)
        super(*args) do |output|
          RakeTasks.from_yaml_file(CommonSpecHelpers.test_settings_file, output: output).tap do |tasks|
            expect(tasks.send(:admin)).to be_a(Admin)
          end
        end
      end
    end
  end
end
