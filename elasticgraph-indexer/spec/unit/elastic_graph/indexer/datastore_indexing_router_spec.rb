# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"
require "elastic_graph/constants"
require "elastic_graph/elasticsearch/client"
require "elastic_graph/indexer/datastore_indexing_router"
require "elastic_graph/indexer/operation/factory"

module ElasticGraph
  class Indexer
    RSpec.describe DatastoreIndexingRouter, :capture_logs do
      let(:main_datastore_client) { instance_spy(Elasticsearch::Client, cluster_name: "main") }
      let(:other_datastore_client) { instance_spy(Elasticsearch::Client, cluster_name: "other") }
      let(:indexer) { build_indexer }
      let(:router) { indexer.datastore_router }
      let(:noop_version_conflict_reason) { "[123]: version conflict, current version [534319179481001] is higher or equal to the one provided [534319179481000]" }

      describe "#source_event_versions_in_index" do
        before do
          stub_msearch_on(main_datastore_client, "main")
          stub_msearch_on(other_datastore_client, "other")
        end

        let(:requested_docs_by_client) { ::Hash.new { |h, k| h[k] = [] } }
        let(:stubbed_versions_by_index_and_id) { {} }
        let(:widget_primary_indexing_op) { new_primary_indexing_op({"type" => "Widget", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value", "created_at" => "2021-08-24T23:30:00Z", "workspace_id" => "ws123"}}) }
        let(:component_primary_indexing_op) { new_primary_indexing_op({"type" => "Component", "id" => "7", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}}) }
        let(:widget_derived_update_op) do
          new_operation(
            {"type" => "Widget", "id" => "4", "version" => 1, "record" => {"id" => "1", "currency" => "USD", "name" => "thing1"}},
            destination_index_def: indexer.datastore_core.index_definitions_by_name.fetch("widget_currencies"),
            update_target: indexer.schema_artifacts.runtime_metadata.object_types_by_name.fetch("Widget").update_targets.first,
            doc_id: "USD"
          )
        end

        it "does not make a request to the datastore if the operations list is empty" do
          expect(router.source_event_versions_in_index([])).to eq({})

          expect(main_datastore_client).not_to have_received(:msearch)
          expect(other_datastore_client).not_to have_received(:msearch)
        end

        it "raises an error when the datastore returns unexpected errors" do
          allow(main_datastore_client).to receive(:msearch) do |request|
            # 4 elements = searches for 2 documents since its a search header + search body for each.
            expect(request.fetch(:body).size).to eq(4)

            {
              "responses" => [
                # These are example failures that we got while implementing the `source_event_versions_in_index` logic before we had it entirely correct.
                # These specific errors should no longer happen but we are using them here as examples of what failures look like.
                {"status" => 400, "error" => {"root_cause" => [{"type" => "null_pointer_exception", "reason" => "type must not be null"}], "type" => "null_pointer_exception", "reason" => "type must not be null"}},
                {"status" => 400, "error" => {"root_cause" => [{"type" => "index_not_found_exception", "reason" => "no such index [widgets]", "resource.type" => "index_expression", "resource.id" => "widgets", "index_uuid" => "_na_", "index" => "widgets"}], "type" => "index_not_found_exception", "reason" => "no such index [widgets]", "resource.type" => "index_expression", "resource.id" => "widgets", "index_uuid" => "_na_", "index" => "widgets"}}
              ]
            }
          end

          expect {
            router.source_event_versions_in_index([widget_primary_indexing_op, component_primary_indexing_op])
          }.to raise_error Errors::IdentifyDocumentVersionsFailedError, a_string_including(
            "null_pointer_exception", "index_not_found_exception"
          )
        end

        context "when configured to index types into separate clusters" do
          let(:indexer) { build_indexer(index_to_clusters: {"components" => {"index_into_clusters" => ["main", "other"]}}) }

          it "queries the version on the appropriate clusters for each operation" do
            stubbed_versions_by_index_and_id[["widgets", widget_primary_indexing_op.doc_id]] = 17
            stubbed_versions_by_index_and_id[["components", component_primary_indexing_op.doc_id]] = 27

            results = router.source_event_versions_in_index([widget_primary_indexing_op, component_primary_indexing_op])

            expect(results).to eq(
              widget_primary_indexing_op => {"main" => [17]},
              component_primary_indexing_op => {"main" => [27], "other" => [27]}
            )

            expect(requested_docs_by_client.keys).to contain_exactly("main", "other")
            expect(requested_docs_by_client["main"]).to contain_exactly(
              doc_version_request_for(widget_primary_indexing_op),
              doc_version_request_for(component_primary_indexing_op)
            )
            expect(requested_docs_by_client["other"]).to contain_exactly(
              doc_version_request_for(component_primary_indexing_op)
            )
          end
        end

        context "when a type is configured with a cluster name that is not itself configured" do
          let(:indexer) do
            build_indexer(index_to_clusters: {
              "components" => {"index_into_clusters" => ["undefined"]},
              "widgets" => {"index_into_clusters" => ["main"]}
            })
          end

          it "avoids querying the unconfigured cluster, and returns `nil` for the version" do
            stubbed_versions_by_index_and_id[["widgets", widget_primary_indexing_op.doc_id]] = 17
            stubbed_versions_by_index_and_id[["components", component_primary_indexing_op.doc_id]] = 27

            results = router.source_event_versions_in_index([widget_primary_indexing_op, component_primary_indexing_op])

            expect(results).to eq(
              widget_primary_indexing_op => {"main" => [17]},
              component_primary_indexing_op => {"undefined" => []}
            )
          end
        end

        it "supports normal updates and derived indexing type update operations" do
          stubbed_versions_by_index_and_id[["widgets", widget_primary_indexing_op.doc_id]] = 17
          stubbed_versions_by_index_and_id[["widget_currencies", widget_derived_update_op.doc_id]] = 33
          stubbed_versions_by_index_and_id[["components", component_primary_indexing_op.doc_id]] = 27

          # Note: we intentionally mix the operations which are ignored and the non-ignored operations to force
          # the implementation to handle them correctly.
          results = router.source_event_versions_in_index([widget_primary_indexing_op, widget_derived_update_op, component_primary_indexing_op])

          expect(requested_docs_by_client.keys).to contain_exactly("main")
          expect(requested_docs_by_client["main"]).to contain_exactly(
            doc_version_request_for(widget_primary_indexing_op),
            doc_version_request_for(component_primary_indexing_op)
          )

          expect(results.keys).to contain_exactly(widget_primary_indexing_op, component_primary_indexing_op, widget_derived_update_op)
          expect(results[widget_primary_indexing_op]).to eq("main" => [17])
          expect(results[component_primary_indexing_op]).to eq("main" => [27])

          # The derived document doesn't keep track of `__versions` so it doesn't have a version it can return.
          expect(results[widget_derived_update_op]).to eq("main" => [])
        end

        def new_primary_indexing_op(event)
          update_targets = indexer
            .schema_artifacts
            .runtime_metadata
            .object_types_by_name
            .fetch(event.fetch("type"))
            .update_targets
            .select { |ut| ut.type == event.fetch("type") }

          expect(update_targets.size).to eq(1)
          index_def = indexer.datastore_core.index_definitions_by_graphql_type.fetch(event.fetch("type")).first

          Operation::Update.new(
            event: event,
            prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
              event.fetch("type"),
              event.fetch("record")
            ),
            destination_index_def: index_def,
            update_target: update_targets.first,
            doc_id: event.fetch("id"),
            destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
          )
        end

        def stub_msearch_on(client, client_name)
          allow(client).to receive(:msearch) do |request|
            requested_docs = request.dig(:body).each_slice(2).map do |(search_header, search_body)|
              # verify we avoid requesting fields we don't need to identify the version
              expect(search_body.dig(:_source, :includes)).to include(a_string_starting_with("__versions."))

              [search_header.fetch(:index), search_body.fetch(:query).fetch(:ids).fetch(:values).first]
            end

            requested_docs_by_client[client_name].concat(requested_docs)

            responses = requested_docs.map do |(index, id)|
              version = stubbed_versions_by_index_and_id[[index, id]]

              relationship = {
                "widgets" => SELF_RELATIONSHIP_NAME,
                "components" => SELF_RELATIONSHIP_NAME,
                "widget_currencies" => "currency"
              }.fetch(index)

              hit = {
                "_index" => index, "_type" => "_doc", "_id" => id, "_source" => {
                  "__versions" => {relationship => {id => version}}
                }
              }

              {"hits" => {"hits" => [hit]}}
            end

            {"responses" => responses}
          end
        end
      end

      def doc_version_request_for(op)
        [
          op.destination_index_def.index_expression_for_search,
          op.doc_id
        ]
      end

      describe "#bulk" do
        # `Router#bulk` delegates to `validate_mapping_completeness_of!` and essentially treats it as a collaborator.
        # Here we express it as a collaborator by essentially providing an alias for it.
        let(:index_mapping_checker) { router }

        before do
          allow(index_mapping_checker).to receive(:validate_mapping_completeness_of!)
          allow(main_datastore_client).to receive(:bulk) { |request| respond_to_datastore_client_bulk_request(request) }
          allow(other_datastore_client).to receive(:bulk) { |request| respond_to_datastore_client_bulk_request(request) }
        end

        let(:widget_derived_update_op) do
          new_operation(
            {"type" => "Widget", "id" => "1", "version" => 1, "record" => {"id" => "1", "currency" => "USD", "name" => "thing1"}},
            destination_index_def: indexer.datastore_core.index_definitions_by_name.fetch("widget_currencies"),
            update_target: indexer.schema_artifacts.runtime_metadata.object_types_by_name.fetch("Widget").update_targets.reject(&:for_normal_indexing?).first,
            doc_id: "USD"
          )
        end

        let(:operations) do
          [
            new_operation({"type" => "Widget", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}}),
            new_operation({"type" => "Widget", "id" => "2", "version" => 1, "record" => {"id" => "2", "some_field" => "value"}}),
            new_operation({"type" => "Component", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}}),
            widget_derived_update_op
          ]
        end

        it "transforms the provided operations into an appropriate bulk body" do
          bulk_request = nil
          allow(main_datastore_client).to receive(:bulk) do |request|
            bulk_request = request
            respond_to_datastore_client_bulk_request(request)
          end

          router.bulk(operations, refresh: true)

          expect(bulk_request).to include(:refresh, :body)
          expect(bulk_request[:refresh]).to eq(true)

          submitted_body = bulk_request[:body]
          expect(submitted_body.size).to eq(8)

          expect(submitted_body[0]).to eq({update: {_id: "1", _index: "widgets", retry_on_conflict: 5}})
          expect(submitted_body[1]).to include(
            script: a_hash_including(id: INDEX_DATA_UPDATE_SCRIPT_ID, params: a_hash_including("data")),
            scripted_upsert: true,
            upsert: {}
          )

          expect(submitted_body[2]).to eq({update: {_id: "2", _index: "widgets", retry_on_conflict: 5}})
          expect(submitted_body[3]).to include(
            script: a_hash_including(id: INDEX_DATA_UPDATE_SCRIPT_ID, params: a_hash_including("data")),
            scripted_upsert: true,
            upsert: {}
          )

          expect(submitted_body[4]).to eq({update: {_id: "1", _index: "components", retry_on_conflict: 5}})
          expect(submitted_body[5]).to include(
            script: a_hash_including(id: INDEX_DATA_UPDATE_SCRIPT_ID, params: a_hash_including("data")),
            scripted_upsert: true,
            upsert: {}
          )

          expect(submitted_body[6]).to eq({update: {_id: "USD", _index: "widget_currencies", retry_on_conflict: 5}})
          expect(submitted_body[7]).to include(
            scripted_upsert: true,
            upsert: {},
            script: a_hash_including(
              id: /WidgetCurrency_from_Widget_/,
              params: {"data" => {"name" => ["thing1"]}, "id" => "USD"}
            )
          )
        end

        it "ignores operations that convert to an empty `to_datastore_bulk`" do
          index_op = new_operation({"type" => "Widget", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}})
          # Note: technically, no operation implementations return an empty `to_datastore_bulk` at this point,
          # but this is still useful behavior for the router to have, so we're using a test double here.
          destination_index_def = indexer.datastore_core.index_definitions_by_name.fetch("widget_currencies")
          empty_update_op = instance_double(
            Indexer::Operation::Update,
            to_datastore_bulk: [],
            destination_index_def: destination_index_def
          )

          result = router.bulk([index_op, empty_update_op], refresh: true).successful_operations_by_cluster_name

          expected_successful_ops = {
            "main" => [index_op]
          }
          expect(result).to eq expected_successful_ops

          # The empty update should not be attempted at all
          expect(main_datastore_client).to have_received(:bulk).with(
            body: index_op.to_datastore_bulk,
            refresh: true
          )
        end

        it "returns failures if `client#bulk` returns any error other than `version_conflict_engine_exception`" do
          # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
          fake_resp = {
            "items" => [
              {"update" => {"status" => 500, "error" => {"reason" => "ERROR"}}},
              success_item,
              success_item,
              success_item
            ]
          }

          allow(main_datastore_client).to receive(:bulk).and_return(fake_resp)

          result = router.bulk(operations, refresh: true)

          expect(result.failure_results.size).to eq 1
          expect(result.failure_results.first).to be_a Operation::Result
          expect(result.failure_results.first.operation).to eq(operations.first)
          expect(result.failure_results.first.inspect).to include("ERROR; full response")
        end

        it "prevents failures from being silently ignored via a `check_failures` argument on the success methods" do
          fake_resp = {
            "items" => [
              {"update" => {"status" => 500, "error" => {"reason" => "ERROR"}}},
              success_item,
              success_item,
              success_item
            ]
          }

          allow(main_datastore_client).to receive(:bulk).and_return(fake_resp)

          result = router.bulk(operations)

          expect {
            result.successful_operations
          }.to raise_error IndexingFailuresError, a_string_including("1 indexing failure", "ERROR")

          expect(result.successful_operations(check_failures: false)).not_to be_empty

          expect {
            result.successful_operations_by_cluster_name
          }.to raise_error IndexingFailuresError, a_string_including("1 indexing failure", "ERROR")

          expect(result.successful_operations_by_cluster_name(check_failures: false)).not_to be_empty
        end

        it "converts a version conflict for an update operation into a noop result" do
          # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
          fake_resp = {
            "items" => [
              success_item,
              success_item,
              success_item,
              noop_item
            ]
          }

          allow(main_datastore_client).to receive(:bulk).and_return(fake_resp)

          result = router.bulk(operations, refresh: true)

          expected_successful_ops = {
            "main" => [operations[0], operations[1], operations[2]]
          }

          expect(result.successful_operations_by_cluster_name).to eq expected_successful_ops
          expect(result.noop_results).to eq [Operation::Result.noop_of(
            operations.last,
            nil
          )]
        end

        it "avoids the I/O cost of writing to the datastore when given an empty list of bulk operations" do
          results = router.bulk([]).successful_operations_by_cluster_name

          expect(results).to eq({})
          expect(main_datastore_client).not_to have_received(:bulk)
        end

        it "does not validate the index mapping consistency of the destination index before performing the bulk request" do
          call_sequence = []
          allow(index_mapping_checker).to receive(:validate_mapping_completeness_of!)

          allow(main_datastore_client).to receive(:bulk) do |request|
            call_sequence << :bulk
            respond_to_datastore_client_bulk_request(request)
          end

          router.bulk(operations)

          expect(call_sequence).to eq [
            :bulk
          ]
        end

        it "includes the exception class and message in the return failure result when scripted updates fail" do
          # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
          fake_resp = {"items" => [
            {
              "update" => {
                "status" => 400,
                "error" => {
                  "reason" => "failed to execute script",
                  "caused_by" => {
                    "caused_by" => {
                      "type" => "illegal_argument_exception",
                      "reason" => "value was null, which is not allowed"
                    }
                  }
                }
              }
            }
          ]}

          allow(main_datastore_client).to receive(:bulk).and_return(fake_resp)

          failure = only_failure_from(router.bulk([widget_derived_update_op]))
          expect(failure.operation).to eq(widget_derived_update_op)
          expect(failure.description).to include(
            "update_WidgetCurrency_from_Widget_",
            "(applied to `USD`): failed to execute script (illegal_argument_exception: value was null, which is not allowed)"
          )
        end

        it "gracefully handles script update errors having `caused_by` details instead of `caused_by.caused_by` details" do
          fake_resp = {"items" => [
            {
              "update" => {
                "status" => 400,
                "error" => {
                  "type" => "illegal_argument_exception",
                  "reason" => "failed to execute script",
                  "caused_by" => {
                    "type" => "resource_not_found_exception",
                    "reason" => "unable to find script [some_script_id] in cluster state"
                  }
                }
              }
            }
          ]}

          allow(main_datastore_client).to receive(:bulk).and_return(fake_resp)

          failure = only_failure_from(router.bulk([widget_derived_update_op]))
          expect(failure.operation).to eq(widget_derived_update_op)
          expect(failure.description).to include(
            "update_WidgetCurrency_from_Widget_",
            "(applied to `USD`): failed to execute script (resource_not_found_exception: unable to find script [some_script_id] in cluster state)"
          )
        end

        it "gracefully handles script update errors having no `caused_by` details" do
          # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
          fake_resp = {"items" => [
            {
              "update" => {
                "status" => 400,
                "error" => {
                  "reason" => "failed for an unknown reason"
                }
              }
            }
          ]}

          allow(main_datastore_client).to receive(:bulk).and_return(fake_resp)

          failure = only_failure_from(router.bulk([widget_derived_update_op]))
          expect(failure.operation).to eq(widget_derived_update_op)
          expect(failure.description).to include(
            "update_WidgetCurrency_from_Widget_",
            "(applied to `USD`): failed for an unknown reason; full response: {",
            "status\": 400"
          )
        end

        def only_failure_from(result)
          expect(result.failure_results.size).to eq(1)
          failure = result.failure_results.first

          expect(failure).to be_a(Operation::Result)
          expect(failure.category).to eq(:failure)

          failure
        end

        context "when configured to index types into separate clusters" do
          let(:indexer) { build_indexer(index_to_clusters: {"components" => {"index_into_clusters" => ["other"]}}) }
          let(:widget_operations) { [operations[0], operations[1], operations[3]] }
          let(:component_operations) { [operations[2]] }

          it "runs the operation for each type using the appropriate client" do
            successful_ops = router.bulk(operations, refresh: true).successful_operations_by_cluster_name

            expect(successful_ops.keys).to contain_exactly("main", "other")
            expect(successful_ops.fetch("main")).to eq(widget_operations)
            expect(successful_ops.fetch("other")).to eq(component_operations)
          end

          it "only returns successful operations across each cluster" do
            # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
            main_fake_resp = {
              "items" => [
                success_item,
                noop_item,
                success_item
              ]
            }

            # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
            other_fake_resp = {
              "items" => [
                noop_item
              ]
            }

            allow(main_datastore_client).to receive(:bulk).and_return(main_fake_resp)
            allow(other_datastore_client).to receive(:bulk).and_return(other_fake_resp)

            result = router.bulk(operations, refresh: true)
            successful_ops = result.successful_operations_by_cluster_name

            expect(successful_ops.fetch("main")).to contain_exactly(operations[0], operations[3])
            expect(successful_ops.fetch("other")).to be_empty
            expect(result.noop_results.size).to be > 0
          end
        end

        context "when a type is configured to index into multiple clusters" do
          let(:indexer) do
            build_indexer(index_to_clusters: {
              "components" => {"index_into_clusters" => ["main", "other"]},
              "widgets" => {"index_into_clusters" => ["main", "other"]}
            })
          end

          it "successfully runs operations using multiple clients" do
            component_op = new_operation({"type" => "Component", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}})
            widget_op = new_operation({"type" => "Widget", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}})
            successful_ops = router.bulk([component_op, widget_op], refresh: true).successful_operations_by_cluster_name

            expect(successful_ops.keys).to contain_exactly("main", "other")
            expect(successful_ops["main"]).to contain_exactly(component_op, widget_op)
            expect(successful_ops["other"]).to contain_exactly(component_op, widget_op)
          end

          it "only returns operation on clusters it successfully ran on" do
            # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
            other_fake_resp = {
              "items" => [
                noop_item,
                success_item
              ]
            }

            allow(other_datastore_client).to receive(:bulk).and_return(other_fake_resp)

            component_op = new_operation({"type" => "Component", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}})
            widget_op = new_operation({"type" => "Widget", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}})

            result = router.bulk([component_op, widget_op], refresh: true)
            successful_ops = result.successful_operations_by_cluster_name

            expect(successful_ops.keys).to contain_exactly("main", "other")
            expect(successful_ops["main"]).to contain_exactly(component_op, widget_op)
            expect(successful_ops["other"]).to contain_exactly(widget_op)
            expect(result.noop_results.size).to be > 0
          end
        end

        context "when a type is configured to index into no clusters" do
          let(:indexer) do
            build_indexer(index_to_clusters: {
              "components" => {"index_into_clusters" => []},
              "widgets" => {"index_into_clusters" => ["main"]}
            })
          end

          it "fails with a clear error before any calls to the datastore are made, because we don't want to drop the event on the floor, and want to treat the batch consistently" do
            expect_inaccessible_error
          end
        end

        context "when a type is configured with a cluster name that is not itself configured" do
          let(:indexer) do
            build_indexer(index_to_clusters: {
              "components" => {"index_into_clusters" => ["main", "undefined"]},
              "widgets" => {"index_into_clusters" => ["main"]}
            })
          end

          it "fails with a clear error before any calls to the datastore are made, because we don't want to drop the event on the floor, and want to treat the batch consistently" do
            expect_inaccessible_error
          end
        end

        def expect_inaccessible_error
          component_op1 = new_operation({"type" => "Component", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}})
          component_op2 = new_operation({"type" => "Component", "id" => "2", "version" => 1, "record" => {"id" => "2", "some_field" => "value"}})
          widget_op1 = new_operation({"type" => "Widget", "id" => "1", "version" => 1, "record" => {"id" => "1", "some_field" => "value"}})
          widget_op2 = new_operation({"type" => "Widget", "id" => "2", "version" => 1, "record" => {"id" => "2", "some_field" => "value"}})

          expect {
            router.bulk([widget_op1, component_op1, component_op2, widget_op2], refresh: true)
          }.to raise_error IndexingFailuresError, a_string_including("configured to be inaccessible", "Component:1@v1", "Component:2@v1")

          expect(main_datastore_client).not_to have_received(:bulk)
        end

        def noop_item
          # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
          {
            "update" => {
              "status" => 200,
              "result" => "noop"
            }
          }
        end

        def success_item
          {"update" => {"status" => 200}}
        end
      end

      def new_operation(event, update_target: nil, **overrides)
        update_target ||= begin
          update_targets = indexer
            .schema_artifacts
            .runtime_metadata
            .object_types_by_name
            .fetch(event.fetch("type"))
            .update_targets
            .select { |ut| ut.type == event.fetch("type") }

          expect(update_targets.size).to eq(1)
          update_targets.first
        end

        index_defs = indexer.datastore_core.index_definitions_by_graphql_type.fetch(event.fetch("type"))
        expect(index_defs.size).to eq 1
        index_def = index_defs.first

        arguments = {
          event: event,
          prepared_record: indexer.record_preparer_factory.for_latest_json_schema_version.prepare_for_index(
            event.fetch("type"),
            event.fetch("record")
          ),
          destination_index_def: index_def,
          update_target: update_target,
          doc_id: event.fetch("id"),
          destination_index_mapping: indexer.schema_artifacts.index_mappings_by_index_def_name.fetch(index_def.name)
        }.merge(overrides)

        Operation::Update.new(**arguments)
      end

      def respond_to_datastore_client_bulk_request(request)
        operation_actions = request
          .fetch(:body)
          .filter_map { |hash| hash.keys.first.to_s if [[:index], [:update]].include?(hash.keys) }

        items = operation_actions.map { |action| success_item }
        # Make sure the stubbed response ONLY contains keys that match the `filter_path` in DATASTORE_BULK_FILTER_PATH
        {"items" => items}
      end

      def build_indexer(index_to_clusters: {})
        super(clients_by_name: {"main" => main_datastore_client, "other" => other_datastore_client}, schema_definition: lambda do |schema|
          schema.object_type "Component" do |t|
            t.field "id", "ID!"
            t.field "some_field", "String!"
            t.index "components"
          end

          schema.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.field "currency", "String"
            t.field "name", "String"
            t.field "some_field", "String!"
            t.index "widgets"
            t.derive_indexed_type_fields "WidgetCurrency", from_id: "currency" do |derive|
              derive.append_only_set "widget_names", from: "name"
            end
          end

          schema.object_type "WidgetCurrency" do |t|
            t.field "id", "ID!"
            t.field "widget_names", "[String!]!"
            t.index "widget_currencies"
          end
        end) do |config|
          config.with(index_definitions: config.index_definitions.merge(
            index_to_clusters.to_h do |index, clusters|
              [index, config_index_def_of(index_into_clusters: clusters["index_into_clusters"])]
            end
          ))
        end
      end
    end
  end
end
