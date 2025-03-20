# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/aggregation/key"

module ElasticGraph
  class GraphQL
    module Aggregation
      RSpec.describe Key do
        let(:delimiter) { Key::DELIMITER }
        let(:path_delimiter) { FieldPathEncoder::DELIMITER }

        describe Key::AggregatedValue do
          it "allows an `AggregatedValue` for an unnested field to be encoded" do
            key = Key::AggregatedValue.new(
              aggregation_name: "my_aggs",
              field_path: ["my_field"],
              function_name: "sum"
            )

            encoded = key.encode
            expect(encoded).to eq "my_aggs:my_field:sum"
          end

          it "allows an `AggregatedValue` for an nested field to be encoded" do
            key = Key::AggregatedValue.new(
              aggregation_name: "my_aggs",
              field_path: ["transaction", "amountMoney", "amount"],
              function_name: "sum"
            )

            encoded = key.encode
            expect(encoded).to eq("my_aggs:transaction.amountMoney.amount:sum")
          end

          it "raises an `Errors::InvalidArgumentValueError` if a field name includes the delimiter" do
            expect {
              Key::AggregatedValue.new(
                aggregation_name: "my_aggs",
                field_path: ["my_#{delimiter}field"],
                function_name: "sum"
              )
            }.to raise_error(Errors::InvalidArgumentValueError, a_string_including("contains delimiter"))
          end

          it "raises an `Errors::InvalidArgumentValueError` if function name includes the delimiter" do
            expect {
              Key::AggregatedValue.new(
                aggregation_name: "my_aggs",
                field_path: ["my_field"],
                function_name: "su#{delimiter}m"
              )
            }.to raise_error(Errors::InvalidArgumentValueError, a_string_including("contains delimiter"))
          end

          it "raises an `Errors::InvalidArgumentValueError` if aggregation name includes the delimiter" do
            expect {
              Key::AggregatedValue.new(
                aggregation_name: "my#{delimiter}aggs",
                field_path: ["my_field"],
                function_name: "sum"
              )
            }.to raise_error(Errors::InvalidArgumentValueError, a_string_including("contains delimiter"))
          end

          it "raises an `Errors::InvalidArgumentValueError` if a field name includes the field path delimiter" do
            expect {
              Key::AggregatedValue.new(
                aggregation_name: "my_aggs",
                field_path: ["my_#{path_delimiter}field"],
                function_name: "sum"
              )
            }.to raise_error(Errors::InvalidArgumentValueError, a_string_including("contains delimiter"))
          end

          describe "#encode" do
            it "returns a non-empty string" do
              encoded = Key::AggregatedValue.new(
                aggregation_name: "my_aggs",
                field_path: ["my_field"],
                function_name: "sum"
              ).encode

              expect(encoded).to be_a(String)
              expect(encoded).not_to eq("")
            end
          end

          it "returns the original `field_path` from `#field_path` in spite of it being stored internally as an encoded path" do
            key = Key::AggregatedValue.new(
              aggregation_name: "my_aggs",
              field_path: ["my_field", "sub_field"],
              function_name: "sum"
            )

            expect(key.field_path).to eq(["my_field", "sub_field"])
            expect(key.encoded_field_path).to eq("my_field.sub_field")
          end
        end

        describe "#extract_aggregation_name_from" do
          it "returns the aggregation name portion of an encoded key" do
            aggregated_value_key = Key::AggregatedValue.new(
              aggregation_name: "my_aggs",
              field_path: ["my_field"],
              function_name: "sum"
            )

            agg_name = Key.extract_aggregation_name_from(aggregated_value_key.encode)

            expect(agg_name).to eq "my_aggs"
          end

          it "returns a string that's not an encoded key as-is" do
            agg_name = Key.extract_aggregation_name_from("by_size")

            expect(agg_name).to eq "by_size"
          end
        end
      end
    end
  end
end
