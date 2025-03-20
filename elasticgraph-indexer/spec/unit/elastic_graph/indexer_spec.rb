# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/indexer"

module ElasticGraph
  RSpec.describe Indexer do
    it "returns non-nil values from each attribute" do
      expect_to_return_non_nil_values_from_all_attributes(build_indexer)
    end

    describe ".from_parsed_yaml" do
      it "builds an Indexer instance from the contents of a YAML settings file" do
        customization_block = lambda { |conn| }
        indexer = Indexer.from_parsed_yaml(parsed_test_settings_yaml, &customization_block)

        expect(indexer).to be_a(Indexer)
        expect(indexer.datastore_core.client_customization_block).to be(customization_block)
      end
    end
  end
end
