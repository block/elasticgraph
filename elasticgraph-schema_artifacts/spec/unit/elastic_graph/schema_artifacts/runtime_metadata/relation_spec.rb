# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/relation"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe Relation do
        include RuntimeMetadataSupport

        it "builds from a minimal hash" do
          relation = Relation.from_hash({"direction" => "in"})

          expect(relation).to eq Relation.new(
            direction: :in,
            foreign_key: nil,
            additional_filter: {},
            foreign_key_nested_paths: []
          )
        end
      end
    end
  end
end
