# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/schema_definition/results"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "Static scripts" do
      describe "the `INDEX_DATA_UPDATE_SCRIPT_ID` constant" do
        it "matches the current id of our static script" do
          expected_id = Results::STATIC_SCRIPT_REPO.script_ids_by_scoped_name.fetch("update/index_data")

          expect(INDEX_DATA_UPDATE_SCRIPT_ID).to eq(expected_id)
        end
      end

      describe "the `UPDATE_WAS_NOOP_MESSAGE_PREAMBLE` constant" do
        it "is used by the `index_data` script at the start of an exception message to indicate a no-op" do
          script = Results::STATIC_SCRIPT_REPO.scripts.find { |s| s.scoped_name == "update/index_data" }

          # We care about the "was a no-op" exception starting with UPDATE_WAS_NOOP_MESSAGE_PREAMBLE because
          # our indexing logic detects this case by looking for a failure with that at the start of it.
          expect(script.source).to include("throw new IllegalArgumentException(\"#{UPDATE_WAS_NOOP_MESSAGE_PREAMBLE}")
        end
      end
    end
  end
end
