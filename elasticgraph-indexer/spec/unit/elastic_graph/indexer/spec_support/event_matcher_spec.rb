# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer/spec_support/event_matcher"
require "rspec/matchers/fail_matchers"

RSpec.describe "The `be_a_valid_elastic_graph_event` matcher", :builds_indexer, :factories, aggregate_failures: false do
  include ::RSpec::Matchers::FailMatchers

  let(:valid_event) { build_upsert_event(:widget) }
  let(:invalid_event) { valid_event.merge("type" => "Unknown") }
  let(:event_with_extra_field) { build_upsert_event(:widget, extra1: 3) }

  shared_examples "common matcher examples" do
    it "passes when positively matched against a valid event" do
      expect(valid_event).to be_a_valid_elastic_graph_event
    end

    it "passes when negatively matched against an invalid event" do
      expect(invalid_event).not_to be_a_valid_elastic_graph_event
    end

    it "fails when positively matched against an invalid event" do
      expect {
        expect(invalid_event).to be_a_valid_elastic_graph_event
      }.to fail_including("expected the event[1] to be a valid ElasticGraph event", "type")
    end

    it "fails when negatively matched against a valid event" do
      expect {
        expect(valid_event).not_to be_a_valid_elastic_graph_event
      }.to fail_including("expected the event[1] not to be a valid ElasticGraph event", "type")
    end
  end

  context "with no block" do
    include_examples "common matcher examples"

    it "allows extra properties" do
      expect(event_with_extra_field).to be_a_valid_elastic_graph_event
    end
  end

  context "with a block that calls `with_unknown_properties_disallowed`" do
    include_examples "common matcher examples"

    it "disallows extra properties" do
      expect(event_with_extra_field).not_to be_a_valid_elastic_graph_event

      expect {
        expect(event_with_extra_field).to be_a_valid_elastic_graph_event
      }.to fail_including("extra1")
    end

    def be_a_valid_elastic_graph_event
      super(&:with_unknown_properties_disallowed)
    end
  end

  def be_a_valid_elastic_graph_event
    super(for_indexer: build_indexer)
  end
end
