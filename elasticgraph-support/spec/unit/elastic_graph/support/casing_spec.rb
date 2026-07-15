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
        it "converts camelCase to snake_case" do
          expect(Casing.to_snake("someWord")).to eq("some_word")
          expect(Casing.to_snake("already_snake")).to eq("already_snake")
        end

        it "prefixes an underscore for a leading uppercase letter, unlike `.to_upper_snake`" do
          expect(Casing.to_snake("FooBar")).to eq("_foo_bar")
        end

        it "treats each letter of a multi-letter acronym as a separate word, unlike `.to_upper_snake`" do
          expect(Casing.to_snake("HTTPResponseCode")).to eq("_h_t_t_p_response_code")
        end

        it "treats a digit as part of the word that precedes it" do
          expect(Casing.to_snake("Sha256Hash")).to eq("_sha256_hash")
        end

        it "prefixes an underscore before each letter of an UPPER_SNAKE_CASE string" do
          expect(Casing.to_snake("UPPER_SNAKE_CASE")).to eq("_u_p_p_e_r__s_n_a_k_e__c_a_s_e")
        end
      end

      describe ".to_camel" do
        it "converts snake_case to camelCase" do
          expect(Casing.to_camel("some_word")).to eq("someWord")
          expect(Casing.to_camel("alreadyCamel")).to eq("alreadyCamel")
        end

        it "leaves a leading underscore intact" do
          expect(Casing.to_camel("_typename")).to eq("_typename")
        end

        it "strips the underscores from an UPPER_SNAKE_CASE string" do
          expect(Casing.to_camel("UPPER_SNAKE_CASE")).to eq("UPPERSNAKECASE")
        end
      end

      describe ".to_title" do
        it "converts snake_case or camelCase to TitleCase" do
          expect(Casing.to_title("some_word")).to eq("SomeWord")
          expect(Casing.to_title("alreadyCamel")).to eq("AlreadyCamel")
          expect(Casing.to_title("AlreadyTitle")).to eq("AlreadyTitle")
        end

        it "leaves a leading underscore intact" do
          expect(Casing.to_title("_typename")).to eq("_typename")
        end

        it "strips the underscores from an UPPER_SNAKE_CASE string" do
          expect(Casing.to_title("UPPER_SNAKE_CASE")).to eq("UPPERSNAKECASE")
        end
      end

      describe ".to_upper_snake" do
        it "converts camelCase or snake_case to UPPER_SNAKE_CASE" do
          expect(Casing.to_upper_snake("someWord")).to eq("SOME_WORD")
          expect(Casing.to_upper_snake("already_snake")).to eq("ALREADY_SNAKE")
        end

        it "adds no leading underscore for a leading uppercase letter, unlike `.to_snake`" do
          expect(Casing.to_upper_snake("FooBar")).to eq("FOO_BAR")
        end

        it "keeps a multi-letter acronym intact as a single word, unlike `.to_snake`" do
          expect(Casing.to_upper_snake("HTTPResponseCode")).to eq("HTTP_RESPONSE_CODE")
        end

        it "treats a digit as part of the word that precedes it" do
          expect(Casing.to_upper_snake("Sha256Hash")).to eq("SHA256_HASH")
        end

        it "leaves an UPPER_SNAKE_CASE string unchanged" do
          expect(Casing.to_upper_snake("UPPER_SNAKE_CASE")).to eq("UPPER_SNAKE_CASE")
        end
      end
    end
  end
end
