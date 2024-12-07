# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "base64"
require "elastic_graph/graphql/decoded_cursor"
require "faker"

module ElasticGraph
  class GraphQL
    RSpec.describe DecodedCursor do
      let(:sort_values) do
        {
          "created_at" => "2019-06-12T12:33:30Z",
          "amount" => ::Faker::Number.between(from: 100, to: 900),
          "id" => ::Faker::Alphanumeric.alpha(number: 20)
        }
      end

      describe "#encode" do
        it "encodes the provided sort fields and values to a URL-safe string" do
          cursor = DecodedCursor.new(sort_values).encode

          expect(cursor).to match(/\A[a-zA-Z0-9_-]{32,128}\z/)
        end

        it "returns the special singleton cursor string when called on the singleton cursor" do
          cursor = DecodedCursor::SINGLETON.encode

          expect(cursor).to eq(SINGLETON_CURSOR)
        end
      end

      describe "#sort_values" do
        it "returns the decoded sort values" do
          decoded = DecodedCursor.new(sort_values).sort_values

          expect(decoded).to eq(sort_values)
        end

        it "returns an empty hash when called on the singleton cursor, even after parsing it" do
          values = DecodedCursor::SINGLETON.sort_values
          expect(values).to eq({})

          values = DecodedCursor.decode!(SINGLETON_CURSOR).sort_values
          expect(values).to eq({})

          values = DecodedCursor.try_decode(SINGLETON_CURSOR).sort_values
          expect(values).to eq({})
        end
      end

      describe ".decode!" do
        it "returns a decoded cursor value" do
          cursor = DecodedCursor.new(sort_values).encode
          decoded = DecodedCursor.decode!(cursor)

          expect(decoded.sort_values).to eq sort_values
        end

        it "returns the special `SINGLETON` value when given the `SINGLETON_CURSOR` string" do
          cursor = DecodedCursor.decode!(SINGLETON_CURSOR)

          expect(cursor).to be DecodedCursor::SINGLETON
        end

        it "raises a clear error when decoding an invalid base64 string" do
          bad_cursor = DecodedCursor.new(sort_values).encode + ' $1!!@#(#@'

          expect {
            DecodedCursor.decode!(bad_cursor)
          }.to raise_error(Errors::InvalidCursorError, a_string_including(bad_cursor))
        end

        it "raises a clear error when decoding a valid base64 string encoding an invalid JSON string" do
          bad_cursor = ::Base64.urlsafe_encode64("[12, 23h", padding: false)

          expect {
            DecodedCursor.decode!(bad_cursor)
          }.to raise_error(Errors::InvalidCursorError, a_string_including(bad_cursor))
        end
      end

      describe ".try_decode" do
        it "returns a decoded cursor value" do
          cursor = DecodedCursor.new(sort_values).encode
          decoded = DecodedCursor.try_decode(cursor)

          expect(decoded.sort_values).to eq sort_values
        end

        it "returns the special `SINGLETON` value when given the `SINGLETON_CURSOR` string" do
          cursor = DecodedCursor.try_decode(SINGLETON_CURSOR)

          expect(cursor).to be DecodedCursor::SINGLETON
        end

        it "raises a clear error when decoding an invalid base64 string" do
          bad_cursor = DecodedCursor.new(sort_values).encode + ' $1!!@#(#@'

          expect(DecodedCursor.try_decode(bad_cursor)).to eq nil
        end

        it "raises a clear error when decoding a valid base64 string encoding an invalid JSON string" do
          bad_cursor = ::Base64.urlsafe_encode64("[12, 23h", padding: false)

          expect(DecodedCursor.try_decode(bad_cursor)).to eq nil
        end
      end

      describe ".factory_from_sort_list" do
        let(:amount) { ::Faker::Number.between(from: 100, to: 900) }
        let(:sort_fields) { %w[created_at amount id] }
        let(:sort_list) do
          [
            {"created_at" => {"order" => "asc"}},
            {"amount" => {"order" => "desc"}},
            {"id" => {"order" => "asc"}}
          ]
        end
        let(:sort_values) { ["2019-06-12T12:33:30Z", amount, ::Faker::Alphanumeric.alpha(number: 20)] }

        it "can be built from a list of `{field => {'order' => direction}}` hashes" do
          factory1 = factory_for_sort_fields(sort_fields)
          factory2 = DecodedCursor::Factory.from_sort_list(sort_list)

          expect(factory2).to eq factory1
        end

        it "raises when attempting to build from an invalid sort list" do
          invalid = {"a" => "asc", "b" => "asc"}

          expect {
            DecodedCursor::Factory.from_sort_list(sort_list + [invalid])
          }.to raise_error(Errors::InvalidSortFieldsError, a_string_including(invalid.inspect))
        end

        it "raises when the same field is in the sort list twice, since the encoded JSON cannot represent that (and the extra usage of the field accomplishes nothing...)" do
          invalid = [
            {"foo" => {"order" => "asc"}},
            {"bar" => {"order" => "desc"}},
            {"foo" => {"order" => "desc"}}
          ]

          expect {
            DecodedCursor::Factory.from_sort_list(invalid)
          }.to raise_error(Errors::InvalidSortFieldsError, a_string_including(invalid.inspect))
        end

        it "requires sorts on nested fields to be flattened in advance by the caller" do
          invalid = {"amount_money" => {"amount" => {"order" => "asc"}}}
          valid = {"amount_money.amount" => {"order" => "asc"}}

          expect {
            DecodedCursor::Factory.from_sort_list(sort_list + [invalid])
          }.to raise_error(Errors::InvalidSortFieldsError, a_string_including(invalid.inspect))

          expect(DecodedCursor::Factory.from_sort_list(sort_list + [valid])).to be_a DecodedCursor::Factory
        end

        it "inspects well" do
          factory = factory_for_sort_fields(sort_fields)

          expect(factory.inspect).to eq "#<data #{DecodedCursor::Factory.name} sort_fields=#{sort_fields.inspect}>"
          expect(factory.to_s).to eq factory.inspect
        end

        it "raises a clear error when the list of values to encode has less than the number of sort fields" do
          factory = factory_for_sort_fields(sort_fields)
          values = sort_values - [amount]

          expect {
            factory.build(values)
          }.to raise_error(Errors::CursorEncodingError, a_string_including(values.inspect, sort_fields.inspect))
        end

        it "raises a clear error when the list of values to encode has more than the number of sort fields" do
          factory = factory_for_sort_fields(sort_fields)
          values = sort_values + ["foo"]

          expect {
            factory.build(values)
          }.to raise_error(Errors::CursorEncodingError, a_string_including(values.inspect, sort_fields.inspect))
        end

        def factory_for_sort_fields(sort_fields)
          DecodedCursor::Factory.new(sort_fields)
        end
      end
    end
  end
end
