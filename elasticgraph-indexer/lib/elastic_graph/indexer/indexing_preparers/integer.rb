# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Indexer
    module IndexingPreparers
      class Integer
        # Here we coerce an integer-valued float like `3.0` to a true integer (e.g. `3`).
        # This is necessary because:
        #
        #   1. If a field is an integer in the datastore mapping, it does not tolerate it coming in
        #      as a float, even if it is integer-valued.
        #   2. While we use JSON schema to validate event payloads before we get here, JSON schema
        #      cannot consistently enforce that we receive true integers for int fields.
        #
        # As https://json-schema.org/understanding-json-schema/reference/numeric.html#integer explains:
        #
        # > **Warning**
        # >
        # > The precise treatment of the “integer” type may depend on the implementation of your
        # > JSON Schema validator. JavaScript (and thus also JSON) does not have distinct types
        # > for integers and floating-point values. Therefore, JSON Schema can not use type alone
        # > to distinguish between integers and non-integers. The JSON Schema specification
        # > recommends, but does not require, that validators use the mathematical value to
        # > determine whether a number is an integer, and not the type alone. Therefore, there
        # > is some disagreement between validators on this point. For example, a JavaScript-based
        # > validator may accept 1.0 as an integer, whereas the Python-based jsonschema does not.
        def self.prepare_for_indexing(value)
          integer = value.to_i
          return integer if value == integer
          raise Errors::IndexOperationError, "Cannot safely coerce `#{value.inspect}` to an integer"
        end
      end
    end
  end
end
