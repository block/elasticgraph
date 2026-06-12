# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/sourced_from_nested_path_segment"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe SourcedFromNestedPathSegment do
        it "converts a list segment to a painless hash with a camelCased `sourceField`" do
          segment = ListPathSegment.new(field: "players", source_field: "playerId")

          expect(segment.to_painless_hash).to eq("field" => "players", "sourceField" => "playerId")
        end

        it "converts an object segment to a painless hash without a `sourceField` (which marks it an object segment)" do
          segment = ObjectPathSegment.new(field: "roster")

          expect(segment.to_painless_hash).to eq("field" => "roster")
        end
      end
    end
  end
end
