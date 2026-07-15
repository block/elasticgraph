# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/support/casing"

module ElasticGraph
  module Support
    RSpec.describe Casing do
      describe ".to_snake" do
        it "converts camelCase to snake_case while preserving existing behavior" do
          expect(Casing.to_snake("someWord")).to eq("some_word")
          expect(Casing.to_snake("FooBar")).to eq("_foo_bar")
          expect(Casing.to_snake("already_snake")).to eq("already_snake")
        end
      end

      describe ".to_camel" do
        it "converts snake_case to camelCase" do
          expect(Casing.to_camel("some_word")).to eq("someWord")
          expect(Casing.to_camel("alreadyCamel")).to eq("alreadyCamel")
          expect(Casing.to_camel("_typename")).to eq("_typename")
        end
      end

      describe ".to_upper_snake" do
        it "converts mixed casing to UPPER_SNAKE_CASE while preserving acronym boundaries" do
          expect(Casing.to_upper_snake("someWord")).to eq("SOME_WORD")
          expect(Casing.to_upper_snake("HTTPResponseCode")).to eq("HTTP_RESPONSE_CODE")
          expect(Casing.to_upper_snake("already_snake")).to eq("ALREADY_SNAKE")
        end
      end
    end
  end
end
