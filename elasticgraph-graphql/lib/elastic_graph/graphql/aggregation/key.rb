# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/graphql/aggregation/field_path_encoder"

module ElasticGraph
  class GraphQL
    module Aggregation
      module Key
        # The datastore only gives us an "aggregation key" (or name) to tie response values back to the part of
        # request it came from. We use this delimiter to encode and decode aggregation keys.
        DELIMITER = ":"

        # Aggregation key implementation used when we're dealing with `aggregated_values`.
        class AggregatedValue < ::Data.define(
          # The name of the aggregation encoded into this key.
          :aggregation_name,
          # The path to the field used by this aggregation (encoded as a string)
          :encoded_field_path,
          # The name of the aggregation function, such as "sum".
          :function_name
        )
          # We encode the field path as part of initialization to enforce an invariant that all `AggregatedValue`
          # instances have valid values for all attributes. `FieldPathEncoder.encode` will raise an exception if
          # the field path is invalid.
          def initialize(aggregation_name:, function_name:, field_path: [], encoded_field_path: FieldPathEncoder.encode(field_path))
            Key.verify_no_delimiter_in(aggregation_name, function_name, *field_path)

            super(
              aggregation_name: aggregation_name,
              encoded_field_path: encoded_field_path,
              function_name: function_name
            )
          end

          def encode
            Key.encode([aggregation_name, encoded_field_path, function_name])
          end

          def field_path
            FieldPathEncoder.decode(encoded_field_path)
          end
        end

        # Encodes the key used for a `missing` aggregation used to provide a bucket for
        # documents that are missing a value for the field being grouped on.
        def self.missing_value_bucket_key(base_key)
          Key.encode([base_key, "m"])
        end

        # Extracts an aggregation name from a string that could either already be an aggregation name, or could
        # be an encoded key. We need this for dealing with the multiple forms that aggregation responses take:
        #
        # - When we use `grouped_by`, we run a composite aggregation that has the aggregation name, and
        #   that shows up as a key directly under `aggregations` in the datastore response.
        # - For aggregations with no `grouped_by`, we encode the aggregation name in the key, and the keys
        #   directly under `aggregations` in the datastore response will take a from like:
        #   `[agg_name]:[field_path]:[function]`.
        #
        # It's also possible for these two forms to be mixed under `aggregations` on a datastore response,
        # where some hash keys are in one form and some are in the other form. This can happen when we run
        # multiple aggregations (some with `grouped_by`, some without) in the same query.
        def self.extract_aggregation_name_from(agg_name_or_key)
          agg_name_or_key.split(DELIMITER, 2).first || agg_name_or_key
        end

        def self.encode(parts)
          parts.join(DELIMITER)
        end

        def self.verify_no_delimiter_in(*parts)
          parts.each do |part|
            if part.to_s.include?(DELIMITER)
              raise Errors::InvalidArgumentValueError, %("#{part}" contains delimiter: "#{DELIMITER}")
            end
          end
        end
      end
    end
  end
end
