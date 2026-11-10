# Copyright 2024 - 2026 Block, Inc.
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
          field = IndexField.from_hash({"type_name" => "Int"})

          expect(field).to eq IndexField.new(source: SELF_RELATIONSHIP_NAME, type_name: "Int")
        end

        it "round-trips the `type_name` through its dumpable hash" do
          field = IndexField.new(source: "other", type_name: "Int")

          expect(IndexField.from_hash(field.to_dumpable_hash)).to eq(field)
        end
      end
    end
  end
end
