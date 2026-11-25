# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/indexer_extension"
require "elastic_graph/spec_support/proto_publisher"

module ElasticGraph
  module ProtoIngestion
    RSpec.describe "Protobuf indexing parity", :builds_indexer, :factories do
      let(:indexer) { build_indexer(schema_artifacts: stock_schema_artifacts) }
      let(:publisher) { SpecSupport::ProtoPublisher.new(stock_schema_artifacts) }

      %i[component widget team address electrical_part mechanical_part].each do |factory|
        it "builds the same datastore operations for a #{factory} published as JSON or protobuf" do
          event = build_upsert_event(factory)
          json = indexer.operation_factory.build(event)
          proto = indexer.operation_factory.build(publisher.round_trip(event))

          expect(json.failed_event_error).to be_nil
          expect(proto.failed_event_error).to be_nil
          expect(proto.operations.map(&:to_datastore_bulk)).to eq(json.operations.map(&:to_datastore_bulk))
        end
      end

      it "builds no derived operations when the record omits its derived IDs" do
        event = publisher.round_trip(build_upsert_event(:widget, __exclude_fields: [:cost, :cost_currency_introduced_on]))

        result = indexer.operation_factory.build(event)

        expect(result.failed_event_error).to be_nil
        expect(result.operations.map { |op| op.update_target.type }).to eq(["Widget"])
      end
    end
  end
end
