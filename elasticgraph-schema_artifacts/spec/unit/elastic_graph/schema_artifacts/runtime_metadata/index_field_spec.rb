# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/index_field"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe IndexField do
        include RuntimeMetadataSupport

        it "builds from a minimal hash" do
          field = IndexField.from_hash({})

          expect(field).to eq IndexField.new(source: SELF_RELATIONSHIP_NAME)
        end
      end
    end
  end
end
