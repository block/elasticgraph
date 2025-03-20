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
    class Schema
      # Represents an enum value within a GraphQL schema.
      class EnumValue < ::Data.define(:name, :type, :runtime_metadata)
        def sort_clauses
          sort_clause = runtime_metadata&.sort_field&.then { |sf| {sf.field_path => {"order" => sf.direction.to_s}} } ||
            raise(Errors::SchemaError, "Runtime metadata provides no `sort_field` for #{type.name}.#{name} enum value.")

          [sort_clause]
        end

        def to_s
          "#<#{self.class.name} #{type.name}.#{name}>"
        end
        alias_method :inspect, :to_s
      end
    end
  end
end
