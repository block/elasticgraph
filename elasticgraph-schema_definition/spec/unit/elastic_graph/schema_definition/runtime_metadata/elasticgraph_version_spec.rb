# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #elasticgraph_version" do
      include_context "RuntimeMetadata support"

      it "records the value of `ElasticGraph::VERSION` in runtime metadata" do
        metadata = define_schema.runtime_metadata

        expect(metadata.elasticgraph_version).to eq(ElasticGraph::VERSION)
      end
    end
  end
end