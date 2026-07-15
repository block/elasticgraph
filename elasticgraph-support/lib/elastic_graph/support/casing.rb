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
    class Casing
      # Converts an identifier to snake_case.
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

      # Converts an identifier to UPPER_SNAKE_CASE, preserving acronym boundaries.
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
