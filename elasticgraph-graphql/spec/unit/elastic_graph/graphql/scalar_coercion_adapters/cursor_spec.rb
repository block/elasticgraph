# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/scalar_coercion_adapters/cursor"

module ElasticGraph
  class GraphQL
    module ScalarCoercionAdapters
      RSpec.describe Cursor do
        describe ".coerce_input" do
          it "accepts string values" do
            result = Cursor.coerce_input("abc123", nil)
            expect(result).to eq("abc123")
          end

          it "accepts nil" do
            result = Cursor.coerce_input(nil, nil)
            expect(result).to be_nil
          end

          it "rejects non-string values by returning nil" do
            expect(Cursor.coerce_input(123, nil)).to be_nil
            expect(Cursor.coerce_input([1, 2, 3], nil)).to be_nil
            expect(Cursor.coerce_input({key: "value"}, nil)).to be_nil
            expect(Cursor.coerce_input(true, nil)).to be_nil
          end
        end

        describe ".coerce_result" do
          it "returns the value as-is" do
            expect(Cursor.coerce_result("abc123", nil)).to eq("abc123")
            expect(Cursor.coerce_result(nil, nil)).to be_nil
          end
        end
      end
    end
  end
end
