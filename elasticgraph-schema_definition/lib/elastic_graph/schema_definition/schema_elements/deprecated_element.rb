# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # @private
      DeprecatedElement = ::Data.define(:schema_def_state, :name, :defined_at, :defined_via) do
        # @implements DeprecatedElement
        def description
          "`#{defined_via}` at #{defined_at.path}:#{defined_at.lineno}"
        end
      end
    end
  end
end
