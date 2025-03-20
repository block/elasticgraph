# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "json"

module ElasticGraph
  module Support
    # Utility module that provides helper methods for generating well-formatted GraphQL syntax.
    #
    # @private
    module GraphQLFormatter
      # Formats the given hash as an argument list. If `args` is empty, returns an empty string.
      # Otherwise, wraps the args list in parens. This allows the returned string to be appended
      # to a field or directive, and it'll correctly use parens (or not) based on if there are args
      # or not.
      def self.format_args(**args)
        return "" if args.empty?
        "(#{serialize(args, wrap_hash_with_braces: false)})"
      end

      # Formats the given value in GraphQL syntax. This method was derived
      # from a similar method from the graphql-ruby gem:
      #
      # https://github.com/rmosolgo/graphql-ruby/blob/v1.11.4/lib/graphql/language.rb#L17-L33
      #
      # We don't want to use that method because it is marked as `@api private`, indicating
      # it could be removed in any release of the graphql gem. If we used it, it could hinder
      # future upgrades.
      #
      # Our implementation here differs in a few ways:
      #
      # - case statement instead of multiple `if value.is_a?` checks (a bit cleaner)
      # - `wrap_hash_with_braces` since we do not want to wrap an args hash with braces.
      # - Readable spacing has been added so we get `foo: [1, 2], bar: 3` instead of `foo:[1,2],bar:3`.
      # - Symbol support has been added. Symbols are converted to strings (with no quotes), allowing
      #   callers to pass them for GraphQL enums.
      # - We've removed the `quirks_mode: true` flag passed to `JSON.generate` since it has been
      #   deprecated for a while: https://github.com/flori/json/issues/309
      def self.serialize(value, wrap_hash_with_braces: true)
        case value
        when ::Hash
          serialized_hash = value.map do |k, v|
            "#{k}: #{serialize v}"
          end.join(", ")

          return serialized_hash unless wrap_hash_with_braces

          "{#{serialized_hash}}"
        when ::Array
          serialized_array = value.map do |v|
            serialize v
          end.join(", ")

          "[#{serialized_array}]"
        when ::Symbol
          value.to_s
        else
          ::JSON.generate(value)
        end
      end
    end
  end
end
