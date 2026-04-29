# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Support
    # Builds `X-Opaque-Id` header values from a finite set of readable parts.
    module OpaqueID
      # Builds an `X-Opaque-Id` header value from the provided opaque-id parts.
      #
      # @param parts [Array<String, nil>] opaque-id parts to normalize and join.
      # @return [String, nil] a semicolon-delimited opaque-id header value, or `nil` if no
      #   meaningful opaque-id parts remain after normalization.
      def self.build_header(parts)
        header = parts.filter_map do |part|
          normalized = part.to_s.strip
          next if normalized.empty?

          normalized.gsub(/[;\r\n]/, ",")
        end.join(";")

        header.empty? ? nil : header
      end
    end
  end
end
