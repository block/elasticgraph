# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/scalar_type"
require "elastic_graph/spec_support/runtime_metadata_support"
require "support/example_extensions/indexing_preparers"
require "support/example_extensions/scalar_coercion_adapters"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe ScalarType do
        include RuntimeMetadataSupport

        it "allows `with:` to be used to update a single attribute" do
          scalar_type = ScalarType.new(
            coercion_adapter_ref: scalar_coercion_adapter1.to_dumpable_hash,
            indexing_preparer_ref: indexing_preparer1.to_dumpable_hash
          )
          expect(scalar_type.load_coercion_adapter).to eq(scalar_coercion_adapter1)

          scalar_type = scalar_type.with(coercion_adapter_ref: scalar_coercion_adapter2.to_dumpable_hash)
          expect(scalar_type.load_coercion_adapter).to eq(scalar_coercion_adapter2)
          expect(scalar_type.load_indexing_preparer).to eq(indexing_preparer1)
        end
      end
    end
  end
end
