# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/datastore_core/index_definition"
require "elastic_graph/errors"

module ElasticGraph
  class DatastoreCore
    module IndexDefinition
      RSpec.shared_examples_for "an IndexDefinition implementation (integration specs)", :builds_admin do
        describe "#searches_could_hit_incomplete_docs?" do
          it "returns `false` on an index that has no `sourced_from` fields" do
            index = define_index

            expect {
              expect(index.searches_could_hit_incomplete_docs?).to be false
            }.not_to change { datastore_requests("main").count }

            # Demonstrate that we cache the value by showing the datastore request count doesn't change
            # when we call `searches_could_hit_incomplete_docs?` with the same client again.
            expect {
              expect(index.searches_could_hit_incomplete_docs?).to be false
            }.not_to change { datastore_requests("main").count }
          end

          it "returns `true` on an index that has `sourced_from` fields, without hitting the datastore (since it is not needed!)" do
            index = define_index do |t|
              t.field "owner_name", "String" do |f|
                f.sourced_from "owner", "name"
              end
            end

            expect {
              expect(index.searches_could_hit_incomplete_docs?).to be true
            }.not_to change { datastore_requests("main").count }

            # Demonstrate that we cache the value by showing the datastore request count doesn't change
            # when we call `searches_could_hit_incomplete_docs?` with the same client again.
            expect {
              expect(index.searches_could_hit_incomplete_docs?).to be true
            }.not_to change { datastore_requests("main").count }
          end

          it "returns `false` on an index that no longer has `sourced_from` fields but used to" do
            define_index do |t|
              t.field "owner_name", "String" do |f|
                f.sourced_from "owner", "name"
              end
            end

            index = define_index

            expect(index.searches_could_hit_incomplete_docs?).to be false
          end

          context "when there are no sources recorded in `_meta` on the index" do
            it "uses the `current_sources` to determine the value" do
              index = define_index(skip_configure_datastore: true)
              expect(index.searches_could_hit_incomplete_docs?).to be false

              index = define_index(skip_configure_datastore: true) do |t|
                t.field "owner_name", "String" do |f|
                  f.sourced_from "owner", "name"
                end
              end
              expect(index.searches_could_hit_incomplete_docs?).to be true
            end
          end

          describe "#mappings_in_datastore" do
            it "returns the mappings in normalized form" do
              index = define_index
              allow(IndexConfigNormalizer).to receive(:normalize_mappings).and_call_original

              mappings = index.mappings_in_datastore(main_datastore_client)

              expect(IndexConfigNormalizer).to have_received(:normalize_mappings).at_least(:once)
              expect(mappings).to eq(IndexConfigNormalizer.normalize_mappings(mappings))
            end
          end

          def define_index(skip_configure_datastore: false, &schema_definition)
            datastore_core = build_datastore_core(schema_definition: lambda do |schema|
              schema.object_type "MyType" do |t|
                t.field "id", "ID!"
                t.field "created_at", "DateTime"
                t.relates_to_one "owner", "Owner", via: "my_type_id", dir: :in do |rel|
                  rel.equivalent_field "created_at"
                end
                schema_definition&.call(t)
                t.index unique_index_name do |i|
                  configure_index(i)
                end
              end

              schema.object_type "Owner" do |t|
                t.field "id", "ID!"
                t.field "name", "String"
                t.field "created_at", "DateTime"
                t.field "my_type_id", "ID"
                t.index "#{unique_index_name}_owners"
              end
            end)

            unless skip_configure_datastore
              build_admin(datastore_core: datastore_core).cluster_configurator.configure_cluster(output_io)
            end

            datastore_core.index_definitions_by_name.fetch(unique_index_name)
          end
        end
      end
    end
  end
end
