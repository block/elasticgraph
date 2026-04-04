# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/field_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe FieldExtension do
        it "returns nil when the core indexing field reference is unavailable" do
          field_class = ::Class.new do
            prepend FieldExtension

            def to_indexing_field_reference
              nil
            end
          end

          expect(field_class.new.to_indexing_field_reference).to be_nil
        end
      end
    end
  end
end
