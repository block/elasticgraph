# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "hashdiff"

module ElasticGraph
  class Indexer
    class HashDiffer
      # Generates a string describing how `old` and `new` differ, similar to a git diff.
      # `ignore_ops` can contain any of `:-`, `:+`, and `:~`; when provided those diff operations
      # will be ignored.
      def self.diff(old, new, ignore_ops: [])
        ignore_op_strings = ignore_ops.map(&:to_s).to_set

        diffs = ::Hashdiff.diff(old, new)
          .reject { |op, path, *vals| ignore_op_strings.include?(_ = op) }

        return if diffs.empty?

        diffs.map do |op, path, *vals|
          suffix = if vals.one?
            vals.first
          else
            vals.map { |v| "`#{v.inspect}`" }.join(" => ")
          end

          "#{op} #{path}: #{suffix}"
        end.join("\n")
      end
    end
  end
end
