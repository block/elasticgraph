# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/admin/cluster_configurator"
require "elastic_graph/schema_definition/results"
require "stringio"
require "yaml"

module ElasticGraph
  class Admin
    RSpec.describe ClusterConfigurator, :uses_datastore do
      # Use a different index name than any other tests use, because most tests expect a specific index
      # configuration (based on `config/schema.graphql`) and we do not want to mess with it here.
      let(:index_definition_name) { unique_index_name }
      let(:schema_def) do
        lambda do |schema|
          schema.object_type "WidgetOptions" do |t|
            t.field "size", "Int"
            t.field "color", "String"
          end

          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "name", "String"
            t.field "options", "WidgetOptions"
            t.index unique_index_name
          end

          schema.object_type "Widget2" do |t|
            t.field "id", "ID!"
            t.index "#{unique_index_name}2"
          end
        end
      end

      it "configures the indices and the desired cluster-wide settings on the clusters configured on the indices" do
        admin = admin_for(schema_def) do |config|
          expect(config.clusters.keys).to include("main", "other1", "other2", "other3")

          config.with(index_definitions: {
            unique_index_name => config_index_def_of(
              query_cluster: "main",
              index_into_clusters: ["other1", "other2"] # does not include `other3`
            ),
            "#{unique_index_name}2" => config_index_def_of(
              query_cluster: "main",
              index_into_clusters: ["other1"] # does not include `other2` or `other3`
            )
          })
        end

        expect {
          configure_cluster(admin)
        }.to change { main_datastore_client.get_index(unique_index_name) }.from({}).to(a_hash_including("mappings"))
          .and change { main_datastore_client.get_index("#{unique_index_name}2") }.from({}).to(a_hash_including("mappings"))

        # We expect 2 cluster settings calls to each cluster because of the need to start and end index maintenance mode.
        # Then we expect the index-specific calls only to the specific clusters configured for those indices.
        expect(tallied_datastore_calls("main")).to include("/_cluster/settings" => 2).and include("/#{unique_index_name}", "/#{unique_index_name}2")
        expect(tallied_datastore_calls("other1")).to include("/_cluster/settings" => 2).and include("/#{unique_index_name}", "/#{unique_index_name}2")
        expect(tallied_datastore_calls("other2")).to include("/_cluster/settings" => 2).and include("/#{unique_index_name}").and exclude("/#{unique_index_name}2")
        expect(tallied_datastore_calls("other3")).to include("/_cluster/settings" => 2).and exclude("/#{unique_index_name}", "/#{unique_index_name}2")

        expect(admin.cluster_configurator.accessible_index_definitions.map(&:name)).to contain_exactly(
          unique_index_name,
          "#{unique_index_name}2"
        )
      end

      it "makes no attempt to configure indices that are inaccessible due to residing on inaccessible clusters" do
        admin = admin_for(schema_def) do |config|
          expect(config.clusters.keys).to contain_exactly("main", "other1", "other2", "other3")

          config.with(index_definitions: {
            unique_index_name => config_index_def_of(
              query_cluster: "main",
              index_into_clusters: ["other1"]
            ),
            "#{unique_index_name}2" => config_index_def_of(
              query_cluster: "undefined",
              index_into_clusters: ["undefined"]
            )
          })
        end

        expect {
          configure_cluster(admin)
        }.to change { main_datastore_client.get_index(unique_index_name) }.from({}).to(a_hash_including("mappings"))
          .and maintain { other3_datastore_client.get_index("#{unique_index_name}2") }

        # We expect 2 cluster settings calls to each cluster because of the need to start and end index maintenance mode.
        # Then we expect the index-specific calls only to the specific clusters configured for those indices.
        expect(tallied_datastore_calls("main")).to include("/_cluster/settings" => 2).and include("/#{unique_index_name}").and exclude("/#{unique_index_name}2")
        expect(tallied_datastore_calls("other1")).to include("/_cluster/settings" => 2).and include("/#{unique_index_name}").and exclude("/#{unique_index_name}2")
        expect(tallied_datastore_calls("other2")).to include("/_cluster/settings" => 2).and exclude("/#{unique_index_name}", "/#{unique_index_name}2")

        expect(admin.cluster_configurator.accessible_index_definitions.map(&:name)).to contain_exactly(unique_index_name)
      end

      it "validates all index configurations before applying any of them, to prevent partial application of index configuration updates" do
        # Setting up a situation that results in validation errors is quite complicated, so here we just
        # intercept `validate` on `IndexDefinitionConfigurator` instances to force them to return errors.
        # (But otherwise the `IndexDefinitionConfigurator`s behave just like real ones).
        allow(IndexDefinitionConfigurator::ForIndex).to receive(:new).and_wrap_original do |original_impl, *args, &block|
          original_impl.call(*args, &block).tap do |index_configurator|
            allow(index_configurator).to receive(:validate).and_return(["Problem 1", "Problem 2"])
          end
        end

        admin = admin_for(schema_def)

        expect {
          configure_cluster(admin)
        }.to maintain { main_datastore_client.get_index(unique_index_name) }
          .and maintain { main_datastore_client.get_index("#{unique_index_name}2") }
          .and raise_error(Errors::ClusterOperationError, a_string_including("Problem 1", "Problem 2"))
      end

      context "when there is a schema artifact script" do
        let(:standard_script_ids) { SchemaDefinition::Results::STATIC_SCRIPT_REPO.script_ids_by_scoped_name.values.to_set }

        let(:admin) do
          admin_for(lambda do |schema|
            schema.object_type "WidgetWorkspace" do |t|
              t.field "id", "ID!"
              t.field "widget_names", "[String!]!"
              t.index "#{unique_index_name}_widget_workspaces"
            end

            schema.object_type "Widget#{unique_index_name}" do |t|
              t.field "id", "ID!"
              t.field "#{unique_index_name}_name", "String"
              t.field "workspace_id", "ID"
              t.index unique_index_name

              t.derive_indexed_type_fields "WidgetWorkspace", from_id: "workspace_id" do |derive|
                # Use `unique_index_name` in a field that goes into the script so that the script id is not used by any
                # other tests; that way we can trust that the manipulations in these tests won't impact other tests.
                derive.append_only_set "widget_names", from: "#{unique_index_name}_name"
              end
            end
          end)
        end

        let(:schema_specific_update_scripts) do
          admin.schema_artifacts.datastore_scripts.select do |id|
            id.start_with?("update_") && !standard_script_ids.include?(id)
          end
        end

        before do
          expect(schema_specific_update_scripts).not_to be_empty # the tests below assume it is non-empty
          delete_all_schema_specific_update_scripts
        end

        it "idempotently stores the script in each datastore cluster" do
          expect {
            configure_cluster(admin)
          }.to change { fetch_schema_specific_update_scripts }.from({}).to(schema_specific_update_scripts)

          script_path = "/_scripts/#{schema_specific_update_scripts.keys.first}"
          expect(tallied_datastore_calls("main")).to include(script_path)
          expect(tallied_datastore_calls("other1")).to include(script_path)
          expect(tallied_datastore_calls("other2")).to include(script_path)
          expect(tallied_datastore_calls("other3")).to include(script_path)

          expect {
            configure_cluster(admin)
          }.to maintain { fetch_schema_specific_update_scripts }
        end

        it "correctly reports what it will do in dry run mode" do
          output = configure_cluster(admin.with_dry_run_datastore_clients)
          expect(output).to include("Stored update script: #{schema_specific_update_scripts.keys.first}")
          expect(fetch_schema_specific_update_scripts).to eq({})

          output = configure_cluster(admin)
          expect(output).to include("Stored update script: #{schema_specific_update_scripts.keys.first}")
          expect(fetch_schema_specific_update_scripts).to eq(schema_specific_update_scripts)

          output = configure_cluster(admin.with_dry_run_datastore_clients)
          expect(output).to exclude("Stored update script")
        end

        it "raises an error rather than mutating the script if a different script with that id already exists" do
          first_script = schema_specific_update_scripts.values.first.fetch("script")

          main_datastore_client.put_script(id: schema_specific_update_scripts.keys.first, context: "update", body: {
            script: first_script.merge(
              "source" => "// a leading comment\n\n" + first_script.fetch("source")
            )
          })

          expect {
            configure_cluster(admin)
          }.to raise_error Errors::ClusterOperationError, a_string_including("already exists in the datastore but has different contents", "a leading comment")

          expect(main_datastore_client.get_index(unique_index_name)).to eq({})

          expect {
            configure_cluster(admin.with_dry_run_datastore_clients)
          }.to raise_error Errors::ClusterOperationError, a_string_including("already exists in the datastore but has different contents", "a leading comment")
        end

        def fetch_schema_specific_update_scripts
          schema_specific_update_scripts.filter_map do |id, artifact_script|
            if (fetched_script = main_datastore_client.get_script(id: id))
              [id, {"context" => artifact_script.fetch("context"), "script" => fetched_script.fetch("script")}]
            end
          end.to_h
        end

        def delete_all_schema_specific_update_scripts
          schema_specific_update_scripts.each do |id, script|
            main_datastore_client.delete_script(id: id)
          end
        end
      end

      def configure_cluster(admin)
        output_io = StringIO.new
        admin.cluster_configurator.configure_cluster(output_io)
        output_io.string
      end

      def admin_for(schema_def, &customize_datastore_config)
        build_admin(schema_definition: schema_def, &customize_datastore_config)
      end

      def tallied_datastore_calls(cluster_name)
        datastore_requests(cluster_name).map { |r| r.url.path }.tally
      end
    end
  end
end
