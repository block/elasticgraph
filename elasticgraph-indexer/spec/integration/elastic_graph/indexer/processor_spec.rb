# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/processor"

module ElasticGraph
  class Indexer
    RSpec.describe Processor, :uses_datastore, :factories, :capture_logs do
      let(:indexer) { build_indexer }

      context "process non-rollover upsert events" do
        describe "upserts" do
          let(:component_1_old) { build_upsert_event(:component, id: "123", name: "old_name") }
          let(:component_1_new) { build_upsert_event(:component, id: "123", name: "new_name", __version: component_1_old.fetch("version") + 1) }
          let(:component_2) { build_upsert_event(:component, id: "456", name: "old_name") }

          it "overwrites earlier versions of a document with a later version of the same document" do
            process_batches([component_1_old], [component_1_new])
            response = search

            expect(get_component_names_from_response(response)).to contain_exactly("new_name")
          end

          it "ignores earlier versions of a document that are processed after later versions" do
            process_batches([component_1_new], [component_1_old])

            response = search

            expect(get_component_names_from_response(response)).to contain_exactly("new_name")
          end

          it "still overwrites earlier versions with later versions when both are in the same batch" do
            process_batches([component_1_old, component_1_new])

            response = search

            expect(get_component_names_from_response(response)).to contain_exactly("new_name")
          end

          it "still ignores earlier versions of a document when both are in the same batch" do
            process_batches([component_1_new, component_1_old])

            response = search

            expect(get_component_names_from_response(response)).to contain_exactly("new_name")
          end

          it "tolerates integer-valued-but-float-typed version values" do
            # Here we use the monotonically increasing version number from `build_upsert_event` but convert it to a float.
            # This is necessary to avoid confusing errors where version numbers on deleted documents "stick around" on
            # the index for some indeterminate period of time after we delete all documents.
            event = build_upsert_event(:component, name: "version_as_float")
            event = event.merge("version" => event.fetch("version").to_f)

            process_batches([event])

            response = search

            expect(get_component_names_from_response(response)).to contain_exactly("version_as_float")
          end

          context "when an event is malformed" do
            let(:valid_event_1) { build_upsert_event(:component, id: "c678", name: "valid1") }
            let(:malformed_event) { build_upsert_event(:component, id: "c789", name: 17) } # name is an integer instead of a string as expected
            let(:valid_event_2) { build_upsert_event(:component, id: "c890", name: "valid2") }

            it "raises an error so the message goes into the DLQ and the issue is surfaced to the oncall engineer, while allowing the valid events to be indexed" do
              expect {
                process_batches([valid_event_1, malformed_event, valid_event_2])
              }.to raise_error IndexingFailuresError, a_string_including("c789").and(excluding("c678", "c890"))

              response = search

              expect(get_component_names_from_response(response)).to contain_exactly("valid1", "valid2")
            end

            it "ignores the malformed event if it has been superseded by an indexed event with the same id and a greater version" do
              process_batches([make_valid(malformed_event, version_offset: -1)])
              expect { process_batches([malformed_event]) }.to raise_error IndexingFailuresError, a_string_including("c789")

              process_batches([make_valid(malformed_event, version_offset: 0)])
              expect { process_batches([malformed_event]) }.to raise_error IndexingFailuresError, a_string_including("c789")

              process_batches([make_valid(malformed_event, version_offset: 1)])
              expect { process_batches([malformed_event]) }.to log_warning a_string_including(
                "Ignoring 1 malformed event",
                EventID.from_event(malformed_event).to_s
              )

              response = search
              expect(get_component_names_from_response(response)).to contain_exactly("same_id_valid_event")
            end

            it "ignores the version of a derived indexing type update when determining if an event has been superseded since the derived document's version is not related to the event version" do
              valid_widget = build_upsert_event(:widget, id: "widget_34512")
              superseded_invalid_widget = update_event(valid_widget, version_offset: -1) do |record|
                record.merge("name" => 18)
              end

              process_batches([valid_widget])

              expect { process_batches([superseded_invalid_widget]) }.to log_warning a_string_including(
                "Ignoring 1 malformed event",
                EventID.from_event(superseded_invalid_widget).to_s
              )
            end

            def make_valid(event, version_offset:)
              update_event(event, version_offset: version_offset) do |record|
                record.merge("name" => "same_id_valid_event")
              end
            end

            def update_event(event, version_offset:, &update)
              event.merge(
                "version" => event.fetch("version") + version_offset,
                "record" => update.call(event.fetch("record"))
              )
            end
          end
        end
      end

      context "process rollover upsert events" do
        describe "upserts" do
          let(:widget_2019_06_02_old) { build_upsert_event(:widget, id: "123", workspace_id: "ws123", name: "2019_06_02_old_name", created_at: "2019-06-02T12:00:00Z") }
          let(:widget_2019_06_02_new) { build_upsert_event(:widget, id: "123", workspace_id: "ws123", name: "2019_06_02_new_name", created_at: "2019-06-02T12:00:00Z", __version: widget_2019_06_02_old.fetch("version") + 1) }
          let(:widget_2020_10_02) { build_upsert_event(:widget, id: "456", name: "2020_10_02_old_name", created_at: "2020-10-02T12:00:00Z") }

          it "writes to different indices/years based on `created_at`" do
            process_batches([widget_2019_06_02_old, widget_2020_10_02])
            response = search(index: "widgets_rollover__*")

            expect(indexes_from_results(response)).to contain_exactly("widgets_rollover__2019", "widgets_rollover__2020")
            expect(source_field_values(response, "id")).to contain_exactly("123", "456")
          end

          it "overwrites earlier versions of a document with a later version of the same document" do
            process_batches([widget_2019_06_02_old], [widget_2019_06_02_new])
            response = search(index: "widgets_rollover__*")

            expect(indexes_from_results(response)).to contain_exactly("widgets_rollover__2019")
            expect(source_field_values(response, "name")).to contain_exactly("2019_06_02_new_name")
          end

          it "ignores earlier versions of a document that are processed after later versions" do
            process_batches([widget_2019_06_02_new], [widget_2019_06_02_old])

            response = search(index: "widgets_rollover__*")

            expect(indexes_from_results(response)).to contain_exactly("widgets_rollover__2019")
            expect(source_field_values(response, "name")).to contain_exactly("2019_06_02_new_name")
          end

          def indexes_from_results(response)
            response.dig("hits", "hits").map { |h| h["_index"] }
          end

          def source_field_values(response, field)
            response.dig("hits", "hits").map { |h| h.dig("_source", field) }
          end
        end
      end

      it "can safely mix `version` values that use `int` vs `long` primitive types inside the datastore JVM" do
        component_1 = build_upsert_event(:component, id: "version-mix-12", name: "name1", __version: 1)
        component_2 = build_upsert_event(:component, id: "version-mix-12", name: "name2", __version: 2**61)
        component_3 = build_upsert_event(:component, id: "version-mix-12", name: "name3", __version: 3)

        process_batches([component_1], [component_2])
        process_batches([component_3])

        response = search
        expect(get_component_names_from_response(response)).to contain_exactly("name2")
      end

      def get_component_names_from_response(response)
        response.dig("hits", "hits")
          .select { |h| h["_index"] == "components" }
          .map { |h| h.dig("_source", "name") }
      end

      def process_batches(*batches, via: indexer)
        batches.each do |batch|
          via.processor.process(batch, refresh_indices: true)
        end
      end

      def search(index: "*")
        main_datastore_client.msearch(body: [{index: index}, {}]).dig("responses", 0)
      end
    end
  end
end
