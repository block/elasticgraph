# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/sort_field"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe SortField do
        include RuntimeMetadataSupport

        it "raises a clear error if `direction` is not `:asc` or `:desc`" do
          sort_field_with(direction: :asc)
          sort_field_with(direction: :desc)

          expect {
            sort_field_with(direction: :fesc)
          }.to raise_error Errors::SchemaError, a_string_including(":fesc", ":asc", ":desc")
        end

        it "can be converted to a datastore sort clause" do
          sort_field = sort_field_with(
            field_path: "path.to.field",
            direction: :desc
          )

          expect(sort_field.to_query_clause).to eq({"path.to.field" => {"order" => "desc"}})
        end

        it "builds from a minimal hash" do
          sort_field = SortField.from_hash({"direction" => "asc"})

          expect(sort_field).to eq SortField.new(direction: :asc, field_path: nil)
        end
      end
    end
  end
end
