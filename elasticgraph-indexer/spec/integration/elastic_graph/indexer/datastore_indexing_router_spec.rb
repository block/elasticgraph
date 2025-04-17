# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/datastore_indexing_router"
require "elastic_graph/support/monotonic_clock"

module ElasticGraph
  class Indexer
    RSpec.describe DatastoreIndexingRouter, :uses_datastore, :capture_logs do
      # Here we disable VCR because we are dealing with `version` numbers.
      # To guarantee that our `router.bulk` calls index the operations, we
      # use monotonically increasing `version` values based on the current
      # system time clock, and have configured VCR to match requests that only
      # differ on the `version` values. However, when VCR is playing back the
      # response will contain the `version` from when the cassette was recorded,
      # which will differ from the version we are dealing with on this run of the
      # test.
      #
      # To avoid odd, confusing failures, we just disable VCR here.
      describe "#source_event_versions_in_index", :factories, :no_vcr do
        shared_examples_for "source_event_versions_in_index" do
          let(:indexer) { build_indexer }
          let(:router) { indexer.datastore_router }
          let(:operation_factory) { indexer.operation_factory }

          it "looks up the document version for each of the specified operations, returning a map of versions by operation" do
            test_documents_of_type(:address) do |op|
              expect(uses_custom_routing?(op)).to eq false
            end
          end

          it "queries the version from the correct shard when the index uses custom shard routing" do
            test_documents_of_type(:widget) do |op|
              expect(uses_custom_routing?(op)).to eq true
            end
          end

          it "returns an empty list of versions when only given an unversioned operation" do
            unversioned_op = build_expecting_success(build_upsert_event(:widget)).find { |op| !op.versioned? }
            expect(unversioned_op).to be_a(Operation::Update)

            expect {
              versions_by_cluster_by_op = router.source_event_versions_in_index([unversioned_op])

              expect(versions_by_cluster_by_op).to eq({unversioned_op => {"main" => []}})
            }.not_to change { datastore_requests("main") }
          end

          it "finds the document on any shard, even if it differs from what the operation's routing key would route to" do
            op1 = build_primary_indexing_op(:widget, id: "mutated_routing_key", workspace_id: "wid1")

            results = router.bulk([op1], refresh: true)
            expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1))

            op2 = build_primary_indexing_op(:widget, id: "mutated_routing_key", workspace_id: "wid2")
            versions_by_cluster_by_op = router.source_event_versions_in_index([op2])

            expect(versions_by_cluster_by_op.keys).to contain_exactly(op2)
            expect(versions_by_cluster_by_op[op2]).to eq("main" => [op1.event.fetch("version")])
          end

          it "finds the document on any index, even if it differs from the operation's target index" do
            op1 = build_primary_indexing_op(:widget, id: "mutated_rollover_timestamp", created_at: "2019-12-03T00:00:00Z")

            results = router.bulk([op1], refresh: true)
            expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1))

            op2 = build_primary_indexing_op(:widget, id: "mutated_rollover_timestamp", created_at: "2023-12-03T00:00:00Z")
            versions_by_cluster_by_op = router.source_event_versions_in_index([op2])

            expect(versions_by_cluster_by_op.keys).to contain_exactly(op2)
            expect(versions_by_cluster_by_op[op2]).to eq("main" => [op1.event.fetch("version")])
          end

          it "logs a warning and returns all versions if multiple copies of the document are found" do
            op1 = build_primary_indexing_op(:widget, id: "mutated_routing_and_timestamp", workspace_id: "wid1", created_at: "2019-12-03T00:00:00Z")
            op2 = build_primary_indexing_op(:widget, id: "mutated_routing_and_timestamp", workspace_id: "wid2", created_at: "2023-12-03T00:00:00Z", __version: op1.event.fetch("version") + 1)

            results = router.bulk([op1, op2], refresh: true)
            expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1, op2))

            expect {
              versions_by_cluster_by_op = router.source_event_versions_in_index([op1])
              expect(versions_by_cluster_by_op.keys).to contain_exactly(op1)
              expect(versions_by_cluster_by_op[op1]).to match("main" => a_collection_containing_exactly(
                op1.event.fetch("version"),
                op2.event.fetch("version")
              ))

              versions_by_cluster_by_op = router.source_event_versions_in_index([op2])
              expect(versions_by_cluster_by_op.keys).to contain_exactly(op2)
              expect(versions_by_cluster_by_op[op2]).to match("main" => a_collection_containing_exactly(
                op1.event.fetch("version"),
                op2.event.fetch("version")
              ))
            }.to log_warning a_string_including("IdentifyDocumentVersionsGotMultipleResults")

            expect(logged_jsons_of_type("IdentifyDocumentVersionsGotMultipleResults")).to contain_exactly(
              a_hash_including(
                "id" => ["mutated_routing_and_timestamp", "mutated_routing_and_timestamp"],
                "routing" => a_collection_containing_exactly("wid1", "wid2"),
                "index" => a_collection_containing_exactly("widgets_rollover__after_2021", "widgets_rollover__2019")
              ),
              a_hash_including(
                "id" => ["mutated_routing_and_timestamp", "mutated_routing_and_timestamp"],
                "routing" => a_collection_containing_exactly("wid1", "wid2"),
                "index" => a_collection_containing_exactly("widgets_rollover__after_2021", "widgets_rollover__2019")
              )
            )
          end
        end

        context "when `use_updates_for_indexing?` is set to false", use_updates_for_indexing: false do
          include_examples "source_event_versions_in_index" do
            it "supports all types of operations" do
              op1 = build_primary_indexing_op(:widget)
              expect(op1).to be_a Operation::Upsert

              op2 = build_expecting_success(build_upsert_event(:widget)).last
              expect(op2).to be_a Operation::Update

              results = router.bulk([op1, op2], refresh: true)
              expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1, op2))

              versions_by_cluster_by_op = router.source_event_versions_in_index([op1, op2])
              expect(versions_by_cluster_by_op.keys).to contain_exactly(op1, op2)
              expect(versions_by_cluster_by_op[op1]).to eq("main" => [op1.event.fetch("version")])
              expect(versions_by_cluster_by_op[op2]).to match("main" => []) # the derived document doesn't keep track of source event versions
            end

            def build_primary_indexing_op(type, **overrides)
              event = build_upsert_event(type, **overrides)
              ops = build_expecting_success(event).grep(Operation::Upsert)
              expect(ops.size).to eq(1)
              ops.first
            end

            def uses_custom_routing?(op)
              op.to_datastore_bulk.first.fetch(:index).key?(:routing)
            end
          end
        end

        shared_examples_for "source_event_versions_in_index when `use_updates_for_indexing?` is set to true" do
          include_examples "source_event_versions_in_index" do
            it "supports both primary indexing operations and derived indexing operations" do
              derived_update, self_update = build_expecting_success(build_upsert_event(:widget))
              expect(derived_update.update_target.type).to eq("WidgetCurrency")
              expect(self_update.update_target.type).to eq("Widget")

              results = router.bulk([derived_update, self_update], refresh: true)
              expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(derived_update, self_update))

              versions_by_cluster_by_op = router.source_event_versions_in_index([derived_update, self_update])
              expect(versions_by_cluster_by_op.keys).to contain_exactly(derived_update, self_update)
              expect(versions_by_cluster_by_op[self_update]).to eq("main" => [derived_update.event.fetch("version")])

              # The derived document doesn't keep track of `__versions` so it doesn't have a version it can return.
              expect(versions_by_cluster_by_op[derived_update]).to eq("main" => [])
            end

            def uses_custom_routing?(op)
              op.to_datastore_bulk.first.fetch(:update).key?(:routing)
            end

            def build_primary_indexing_op(type, **overrides)
              event = build_upsert_event(type, **overrides)
              ops = build_expecting_success(event).select { |op| op.update_target.for_normal_indexing? }
              expect(ops.size).to eq(1)
              ops.first
            end
          end
        end

        context "when `use_updates_for_indexing?` is set to true", use_updates_for_indexing: true do
          include_examples "source_event_versions_in_index when `use_updates_for_indexing?` is set to true"
        end

        def test_documents_of_type(type, &block)
          op1 = build_primary_indexing_op(type).tap(&block)
          op2 = build_primary_indexing_op(type).tap(&block)
          op3 = build_primary_indexing_op(type).tap(&block)

          results = router.bulk([op1, op2], refresh: true)

          expect(results.successful_operations_by_cluster_name).to match("main" => a_collection_containing_exactly(op1, op2))

          versions_by_cluster_by_op = router.source_event_versions_in_index([])
          expect(versions_by_cluster_by_op).to eq({})

          versions_by_cluster_by_op = router.source_event_versions_in_index([op1, op2, op3])
          expect(versions_by_cluster_by_op.keys).to contain_exactly(op1, op2, op3)
          expect(versions_by_cluster_by_op[op1]).to eq("main" => [op1.event.fetch("version")])
          expect(versions_by_cluster_by_op[op2]).to eq("main" => [op2.event.fetch("version")])
          expect(versions_by_cluster_by_op[op3]).to eq("main" => [])
        end

        def build_expecting_success(event, **options)
          result = operation_factory.build(event, **options)
          # :nocov: -- our norm is to have no failure
          raise result.failed_event_error if result.failed_event_error
          # :nocov:
          result.operations
        end
      end

      describe "#validate_mapping_completeness_of!" do
        shared_examples_for "validate_mapping_completeness_of!" do |up_to_date_index_name, rollover:|
          let(:monontonic_now_time) { 100_000 }
          let(:monotonic_clock) { instance_double(Support::MonotonicClock, now_in_ms: monontonic_now_time) }
          let(:person_schema_definition) do
            lambda do |schema|
              schema.object_type "Degree" do |t|
                t.field "title", "String"
              end

              schema.object_type "Person" do |t|
                t.field "id", "ID!"
                t.field "created_at", "DateTime"
                t.field "graduate_degrees", "[Degree!]!" do |f|
                  f.mapping type: "object"
                end
                t.field "postgraduate_degrees", "[Degree!]!" do |f|
                  f.mapping type: "nested"
                end
                t.index unique_index_name do |i|
                  i.rollover :monthly, "created_at" if rollover
                end
              end
            end
          end

          it "does not raise an error when the schema is up-to-date in the datastore, and caches that fact so we don't have to re-query the datastore over and over for this" do
            index_def, router = index_def_and_router_for(up_to_date_index_name)

            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to make_datastore_calls("main")

            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to make_no_datastore_calls("main")
          end

          it "raises an error when the schema is not up-to-date in the datastore, and caches that fact for a period so we don't have to re-query the datastore over and over for this", :expect_warning_logging do
            index_def, router = index_def_and_router_for(unique_index_name, schema_definition: person_schema_definition) do |config|
              config.with(index_definitions: {
                unique_index_name => config_index_def_of(index_into_clusters: ["main"])
              })
            end

            simulate_mapping_fetch_network_failure = false
            allow(index_def).to receive(:mappings_in_datastore).and_wrap_original do |original_method, *args, **options|
              raise Errors::RequestExceededDeadlineError, "Timed out" if simulate_mapping_fetch_network_failure
              original_method.call(*args, **options)
            end

            now_in_ms = monontonic_now_time
            allow(monotonic_clock).to receive(:now_in_ms) { now_in_ms }

            cache_expiration_message_snippet = "Mapping cache expired for #{unique_index_name}"

            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))
              .and make_datastore_calls("main")

            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))
              .and make_no_datastore_calls("main")

            expect(logged_output).not_to include(cache_expiration_message_snippet, "Errors::RequestExceededDeadlineError")

            now_in_ms += DatastoreIndexingRouter::MAPPING_CACHE_MAX_AGE_IN_MS_RANGE.max + 1
            simulate_mapping_fetch_network_failure = true

            # After the cache expiration time has elapsed, it should attempt to refetch the mapping.
            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))

            # While that fetching failed, it should merely be reflected in a log message.
            expect(logged_warnings.join).to include(cache_expiration_message_snippet, "got an error", "Errors::RequestExceededDeadlineError")
            flush_logs

            now_in_ms += DatastoreIndexingRouter::MAPPING_CACHE_MAX_AGE_IN_MS_RANGE.max / 2

            # ...and it should not attempt another refetch until the cache age elapses again.
            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))
              .and make_no_datastore_calls("main")

            expect(logged_output).not_to include(cache_expiration_message_snippet, "Errors::RequestExceededDeadlineError")

            now_in_ms += DatastoreIndexingRouter::MAPPING_CACHE_MAX_AGE_IN_MS_RANGE.max
            simulate_mapping_fetch_network_failure = false

            # Now that the cache age has passed, it should attempt to refetch it again.
            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))
              .and make_datastore_calls("main")

            expect(logged_output).to include(cache_expiration_message_snippet).and exclude("got an error", "Errors::RequestExceededDeadlineError")
          end

          it "validates the appropriate datastore clusters based on the passed argument" do
            index_def, router = index_def_and_router_for(unique_index_name, schema_definition: person_schema_definition) do |config|
              config.with(index_definitions: {
                unique_index_name => config_index_def_of(
                  index_into_clusters: ["other1", "other2"],
                  query_cluster: "main"
                )
              })
            end

            expect {
              router.validate_mapping_completeness_of!(:accessible_cluster_names_to_index_into, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))
              .and make_no_datastore_calls("main")
              .and make_datastore_calls("other1")
              .and make_datastore_calls("other2")

            expect {
              router.validate_mapping_completeness_of!(:accessible_cluster_names_to_index_into, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))
              .and make_no_datastore_calls("main")
              .and make_no_datastore_calls("other1")
              .and make_no_datastore_calls("other2")

            expect {
              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            }.to raise_error(a_string_including("mappings are incomplete", unique_index_name, "+ properties"))
              .and make_datastore_calls("main")
              .and make_no_datastore_calls("other1")
              .and make_no_datastore_calls("other2")
          end

          define_method :index_def_config_and_router_for do |index_name, **options, &block|
            indexer = build_indexer(monotonic_clock: monotonic_clock, **options, &block)
            index_def = indexer.datastore_core.index_definitions_by_name.fetch(index_name)

            expect(index_def.rollover_index_template?).to eq(rollover)
            index_config =
              if rollover
                indexer.schema_artifacts.index_templates.fetch(index_name)
              else
                indexer.schema_artifacts.indices.fetch(index_name)
              end

            [index_def, index_config, indexer.datastore_router]
          end

          def index_def_and_router_for(index_name, **options, &block)
            index_def, _config, router = index_def_config_and_router_for(index_name, **options, &block)
            [index_def, router]
          end
        end

        context "with a non-rollover index" do
          include_examples "validate_mapping_completeness_of!", "addresses", rollover: false do
            it "tolerates the index having an extra field that is not in the schema artifacts since we just ignore it and Elasticsearch/OpenSearch do not allow mapping removals" do
              index_def, index_config, router = index_def_config_and_router_for(unique_index_name, schema_definition: person_schema_definition) do |config|
                config.with(index_definitions: {
                  unique_index_name => config_index_def_of(index_into_clusters: ["main"])
                })
              end

              props_with_extra_field = index_config.dig("mappings", "properties").merge(
                "name" => {"type" => "keyword"}
              )

              expect {
                index_config = index_config.merge(
                  "mappings" => index_config["mappings"].merge("properties" => props_with_extra_field)
                )
              }.to change { index_config.dig("mappings", "properties").keys }
                .from(a_collection_excluding("name"))
                .to(a_collection_including("name"))

              main_datastore_client.create_index(index: index_def.name, body: index_config)

              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            end
          end
        end

        context "with a rollover index" do
          include_examples "validate_mapping_completeness_of!", "widgets", rollover: true do
            it "also validates any related indices (e.g. concrete indices created from the rollover template)" do
              index_def, router = index_def_and_router_for(unique_index_name, schema_definition: person_schema_definition) do |config|
                config.with(index_definitions: {
                  unique_index_name => config_index_def_of(setting_overrides_by_timestamp: {
                    "2020-01-01T00:00:00Z" => {}
                  })
                })
              end

              expect(index_def.related_rollover_indices(main_datastore_client).map(&:name)).to eq [
                "#{unique_index_name}_rollover__2020-01"
              ]

              expect {
                router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
              }.to raise_error(a_string_including(
                "On cluster `main` and index/template `#{unique_index_name}`",
                "On cluster `main` and index/template `#{unique_index_name}_rollover__2020-01`"
              ))
            end

            it "tolerates the index having an extra field that is not in the schema artifacts since we just ignore it and Elasticsearch/OpenSearch do not allow mapping removals" do
              index_def, index_config, router = index_def_config_and_router_for(unique_index_name, schema_definition: person_schema_definition) do |config|
                config.with(index_definitions: {
                  unique_index_name => config_index_def_of(index_into_clusters: ["main"])
                })
              end

              props_with_extra_field = index_config.dig("template", "mappings", "properties").merge(
                "name" => {"type" => "keyword"}
              )

              expect {
                index_config = index_config.merge("template" => {
                  "mappings" => index_config.dig("template", "mappings").merge("properties" => props_with_extra_field),
                  "settings" => index_config.dig("template", "settings")
                })
              }.to change { index_config.dig("template", "mappings", "properties").keys }
                .from(a_collection_excluding("name"))
                .to(a_collection_including("name"))

              main_datastore_client.put_index_template(name: index_def.name, body: index_config)

              router.validate_mapping_completeness_of!(:all_accessible_cluster_names, index_def)
            end
          end
        end

        it "can be passed multiple index definitions to verify them all" do
          indexer = build_indexer
          widgets_index = indexer.datastore_core.index_definitions_by_name.fetch("widgets")
          addresses_index = indexer.datastore_core.index_definitions_by_name.fetch("addresses")

          datastore_requests("main").clear

          indexer.datastore_router.validate_mapping_completeness_of!(:all_accessible_cluster_names, widgets_index, addresses_index)

          expect(datastore_requests("main").map(&:description).join("\n")).to include("GET /_index_template/widgets", "GET /addresses")
        end
      end
    end
  end
end
