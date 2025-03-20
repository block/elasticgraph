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
    # Responsible for encoding `Untyped` values into strings. This logic lives here in `elasticgraph-support`
    # so that it can be shared between the `Untyped` indexing preparer (which lives in `elasticgraph-indexer`)
    # and the `Untyped` coercion adapter (which lives in `elasticgraph-graphql`). It is important that these
    # share the same logic so that the string values we attempt to filter on at query time match the string values
    # we indexed when given the semantically equivalent untyped data.
    #
    # Note: change this class with care. Changing the behavior to make `encode` produce different strings may result
    # in breaking queries if the `Untyped`s stored in the index were indexed using previous encoding logic.
    # A backfill into the datastore will likely be required to avoid this issue.
    #
    # @private
    module UntypedEncoder
      # Encodes the given untyped value to a String so it can be indexed in a Elasticsearch/OpenSearch `keyword` field.
      def self.encode(value)
        return nil if value.nil?
        # Note: we use `fast_generate` here instead of `generate`. They basically act the same, except
        # `generate` includes an extra check for self-referential data structures. `value` here ultimately
        # comes out of a parsed JSON document (e.g. either from an ElasticGraph event at indexing time, or
        # as a GraphQL query variable at search time), and JSON cannot express self-referential data
        # structures, so we do not have to worry about that happening.
        #
        # ...but even if it did, we would get an error either way: `JSON.generate` would raise
        # `JSON::NestingError` whereas `:JSON.fast_generate` would give us a `SystemStackError`.
        ::JSON.fast_generate(canonicalize(value))
      end

      # Decodes a previously encoded Untyped value, returning its original value.
      def self.decode(string)
        return nil if string.nil?
        ::JSON.parse(string)
      end

      # Helper method that converts `value` to a canonical form before we dump it as JSON.
      # We do this because we index each JSON value as a `keyword` in the index, and we want
      # equality filters on a JSON value field to consider equivalent JSON objects to be equal
      # even if their normally generated JSON is not the same. For example, we want ElasticGraph
      # to treat these two as being equivalent:
      #
      # {"a": 1, "b": 2} vs {"b": 2, "a": 1}
      #
      # To achieve this, we ensure JSON objects are generated in sorted order, and we use this same
      # logic both at indexing time and also at query time when we are filtering.
      private_class_method def self.canonicalize(value)
        case value
        when ::Hash
          value
            .sort_by { |k, v| k.to_s }
            .to_h { |k, v| [k, canonicalize(v)] }
        when ::Array
          value.map { |v| canonicalize(v) }
        else
          value
        end
      end
    end
  end
end
