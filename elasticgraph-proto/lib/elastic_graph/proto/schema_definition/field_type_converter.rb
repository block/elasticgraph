# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module Proto
    module SchemaDefinition
      # Converts non-list ElasticGraph field types to protobuf field types.
      class FieldTypeConverter
        def self.convert(field_type)
          type = field_type.unwrap_non_null

          if type.list?
            raise Errors::SchemaError, "FieldTypeConverter only supports non-list types, but got list type `#{field_type}`."
          end

          resolved = type.resolved
          unless resolved&.respond_to?(:to_proto_field_type)
            raise Errors::SchemaError, "Type `#{type.unwrapped_name}` cannot be converted to proto. Add a `to_proto_field_type` extension for it."
          end

          resolved.to_proto_field_type
        end
      end
    end
  end
end
