# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/indexing/field_reference"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      module Indexing
        RSpec.describe FieldReference do
          it "returns nil when the wrapped field reference cannot be resolved" do
            unresolved_field_reference = ::Object.new
            unresolved_field_reference.define_singleton_method(:resolve) { nil }

            field_reference = described_class.new(
              field_reference: unresolved_field_reference,
              json_schema_layers: [],
              json_schema_customizations: {}
            )

            expect(field_reference.resolve).to be_nil
          end
        end
      end
    end
  end
end
