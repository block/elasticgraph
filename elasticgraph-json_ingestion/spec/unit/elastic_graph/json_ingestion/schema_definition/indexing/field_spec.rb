# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        RSpec.describe Field do
          it "returns nil for unexpected JSON schema layers" do
            field = described_class.new(
              ::Object.new,
              json_schema_layers: [],
              json_schema_customizations: {}
            )

            expect(field.send(:process_layer, :unexpected, {"type" => "string"})).to be_nil
          end
        end
      end
    end
  end
end
