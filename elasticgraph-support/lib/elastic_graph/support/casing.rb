# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # Provides shared identifier casing conversions.
    #
    # @private
    class Casing
      # Converts an identifier to snake_case. Treats every uppercase letter as the start of a
      # new word: a multi-letter acronym gets split into one "word" per letter, and a leading
      # uppercase letter produces a leading underscore (`"HTTPResponse"` becomes
      # `"_h_t_t_p_response"`). Contrast with {.to_upper_snake}, which keeps acronyms intact.
      #
      # @param name [String] identifier to convert
      # @return [String] converted identifier
      def self.to_snake(name)
        name.gsub(/([[:upper:]])/) do
          uppercase_letter = $1 # : ::String
          "_#{uppercase_letter.downcase}"
        end
      end

      # Converts an identifier to camelCase.
      #
      # @param name [String] identifier to convert
      # @return [String] converted identifier
      def self.to_camel(name)
        name.gsub(/(?<=\w)_(\w)/) do
          letter_after_underscore = $1 # : ::String
          letter_after_underscore.upcase
        end
      end

      # Converts an identifier to TitleCase.
      #
      # @param name [String] identifier to convert
      # @return [String] converted identifier
      def self.to_title(name)
        to_camel(name).sub(/\A(\w)/, &:upcase)
      end

      # Downcases the first letter of an identifier, leaving the rest unchanged
      # (`"WidgetCurrency"` becomes `"widgetCurrency"`).
      #
      # @param name [String] identifier to convert
      # @return [String] converted identifier
      def self.uncapitalize(name)
        name.sub(/\A(\w)/, &:downcase)
      end

      # Converts an identifier to UPPER_SNAKE_CASE. In contrast to {.to_snake}, a multi-letter
      # acronym is kept intact as a single word, and a leading uppercase letter does not produce
      # a leading underscore (`"HTTPResponse"` becomes `"HTTP_RESPONSE"`). A digit is treated as
      # part of the word that precedes it (`"Sha256Hash"` becomes `"SHA256_HASH"`).
      #
      # @param name [String] identifier to convert
      # @return [String] converted identifier
      def self.to_upper_snake(name)
        name
          .gsub(/([[:upper:]]+)([[:upper:]][[:lower:]])/, "\\1_\\2")
          .gsub(/([[:lower:]\d])([[:upper:]])/, "\\1_\\2")
          .upcase
      end
    end
  end
end
