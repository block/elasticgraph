# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/enum"
require "elastic_graph/spec_support/runtime_metadata_support"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      module Enum
        RSpec.describe Type do
          include RuntimeMetadataSupport

          it "builds from a minimal hash" do
            enum_type = Enum::Type.from_hash({})

            expect(enum_type).to eq Enum::Type.new(values_by_name: {})
          end
        end

        RSpec.describe Value do
          include RuntimeMetadataSupport

          it "builds from a minimal hash" do
            enum_value = Enum::Value.from_hash({})

            expect(enum_value).to eq Enum::Value.new(
              sort_field: nil,
              datastore_value: nil,
              datastore_abbreviation: nil,
              alternate_original_name: nil
            )
          end
        end
      end
    end
  end
end
