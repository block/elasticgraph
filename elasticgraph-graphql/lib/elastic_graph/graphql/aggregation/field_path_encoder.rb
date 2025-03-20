# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  class GraphQL
    module Aggregation
      module FieldPathEncoder
        # Embedded fields need to be specified with dot separators.
        DELIMITER = "."

        # Takes a list of field names (e.g., ["amountMoney", "amount"])
        # and returns a single field name path string (e.g., "amountMoney.amount").
        def self.encode(field_names)
          field_names.each do |str|
            verify_delimiters(str)
          end

          join(field_names)
        end

        # Joins together a list of encoded paths.
        def self.join(encoded_paths)
          encoded_paths.join(DELIMITER)
        end

        # Takes a field path (e.g., "amountMoney.amount") and returns the field name parts
        # (["amountMoney", "amount"]).
        def self.decode(field_path)
          field_path.split(DELIMITER)
        end

        private_class_method def self.verify_delimiters(str)
          if str.to_s.include?(DELIMITER)
            raise Errors::InvalidArgumentValueError, %("#{str}" contains delimiter: "#{DELIMITER}")
          end
        end
      end
    end
  end
end
