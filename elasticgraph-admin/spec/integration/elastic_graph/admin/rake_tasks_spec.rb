# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/rake_tasks"
require "elastic_graph/constants"

module ElasticGraph
  class Admin
    RSpec.describe RakeTasks, :rake_task do
      describe "clusters:configure", :uses_datastore do
        describe ":perform" do
          it "updates the settings and mappings in the datastore, then verifies the index consistency" do
            admin = build_admin

            expect {
              output = run_rake(admin, "clusters:configure:perform")
              expect(output.lines).to include a_string_including("Finished updating datastore clusters.")
            }.to change { main_datastore_client.get_index(unique_index_name) }.from({}).to(a_hash_including("mappings"))
              .and change { main_datastore_client.get_index("#{unique_index_name}2") }.from({}).to(a_hash_including("mappings"))
              .and change { datastore_write_requests("main") }

            expect(admin.datastore_indexing_router).to have_received(:validate_mapping_completeness_of!).with(
              :all_accessible_cluster_names,
              an_object_having_attributes(name: unique_index_name),
              an_object_having_attributes(name: "#{unique_index_name}2")
            )
          end

          it "works when the cluster configuration has omitted a named cluster" do
            admin = build_admin(index_definitions: {
              unique_index_name => config_index_def_of,
              "#{unique_index_name}2" => config_index_def_of(
                # `undefined` is not in the `clusters` map
                query_cluster: "undefined",
                index_into_clusters: ["undefined"]
              )
            })

            expect {
              output = run_rake(admin, "clusters:configure:perform")
              expect(output.lines).to include a_string_including("Finished updating datastore clusters.")
            }.to change { main_datastore_client.get_index(unique_index_name) }.from({}).to(a_hash_including("mappings"))
              .and maintain { main_datastore_client.get_index("#{unique_index_name}2") }.from({})
              .and change { datastore_write_requests("main") }

            expect(admin.datastore_indexing_router).to have_received(:validate_mapping_completeness_of!).with(
              :all_accessible_cluster_names,
              an_object_having_attributes(name: unique_index_name)
            )
          end
        end

        describe ":dry_run" do
          it "dry-runs the settings and mappings in the datastore, but does not verify the index consistency" do
            admin = build_admin

            expect {
              output = run_rake(admin, "clusters:configure:dry_run")
              expect(output.lines.join("\n")).to include("dry-run", unique_index_name, "#{unique_index_name}2")
            }.to maintain { main_datastore_client.get_index(unique_index_name) }.from({})
              .and maintain { main_datastore_client.get_index("#{unique_index_name}2") }.from({})
              .and make_no_datastore_write_calls("main")

            expect(admin.datastore_indexing_router).not_to have_received(:validate_mapping_completeness_of!)
          end
        end

        def build_admin(**config_overrides)
          schema_def = lambda do |schema|
            schema.object_type "Money" do |t|
              t.field "currency", "String"
              t.field "amount_cents", "Int"
            end

            schema.object_type "Widget" do |t|
              t.field "id", "ID!"
              t.field "fees", "[Money!]!" do |f|
                f.mapping type: "object"
              end
              t.index unique_index_name
            end

            schema.object_type "Widget2" do |t|
              t.field "id", "ID!"
              t.field "fees", "[Money!]!" do |f|
                f.mapping type: "nested"
              end
              t.index "#{unique_index_name}2"
            end
          end

          super(schema_definition: schema_def, **config_overrides).tap do |admin|
            allow(admin.datastore_indexing_router).to receive(:validate_mapping_completeness_of!).and_call_original
          end
        end
      end

      def run_rake(admin, *args)
        super(*args) do |output|
          RakeTasks.new(output: output) { admin }
        end
      end
    end
  end
end
