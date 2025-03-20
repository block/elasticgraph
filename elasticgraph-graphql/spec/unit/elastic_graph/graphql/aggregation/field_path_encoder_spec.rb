# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/field_path_encoder"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe FieldPathEncoder do
        let(:path_delimiter) { FieldPathEncoder::DELIMITER }

        describe "#encode" do
          it "encodes a list of field names as a single path string with dots separating the parts" do
            encoded = FieldPathEncoder.encode(["a", "b"])
            expect(encoded).to eq("a.b")
          end

          it "raises an `Errors::InvalidArgumentValueError` if a field name includes the field path delimiter" do
            expect {
              FieldPathEncoder.encode(["my_#{path_delimiter}field"])
            }.to raise_error(Errors::InvalidArgumentValueError, a_string_including("contains delimiter"))
          end
        end

        describe "#join" do
          it "encodes a list of field names as a single path string with dots separating the parts" do
            encoded = FieldPathEncoder.join(["a", "b"])
            expect(encoded).to eq("a.b")
          end

          it "encodes a list of field paths as a single path string with dots separating the parts" do
            encoded = FieldPathEncoder.join(["a.b", "c.d"])
            expect(encoded).to eq("a.b.c.d")
          end
        end

        it "encodes and decodes a field path with a single field name part for a root field" do
          field_names = FieldPathEncoder.decode(FieldPathEncoder.encode(["my_field"]))

          expect(field_names).to eq(["my_field"])
        end

        it "encodes and decodes a field path with a listed of field name parts for a nested field" do
          field_names = FieldPathEncoder.decode(FieldPathEncoder.encode(["transaction", "amountMoney", "amount"]))

          expect(field_names).to eq(["transaction", "amountMoney", "amount"])
        end
      end
    end
  end
end
