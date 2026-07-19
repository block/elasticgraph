# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      # Holds the proto ingestion extension's schema definition state.
      #
      # @private
      class ProtoIngestionState < ::Struct.new(:schema_def_state, :package_name, :type_name_by_proto_name)
        def initialize(schema_def_state:, package_name:)
          super(schema_def_state:, package_name:, type_name_by_proto_name: {})
        end

        # Registers the protobuf name for a schema type, raising immediately if it collides with a prior type.
        #
        # @return [void]
        def register_proto_type_name(proto_name, type_name)
          # Artifact generation creates throw-away derived types after the user definition is complete. Those types
          # cannot be rendered into the proto, and some are instantiated more than once, so skip collision tracking.
          return if schema_def_state.user_definition_complete

          if (existing_type_name = type_name_by_proto_name[proto_name])
            raise Errors::SchemaError, "Type names `#{existing_type_name}` and `#{type_name}` both map to the same " \
              "proto type name `#{proto_name}`."
          end

          type_name_by_proto_name[proto_name] = type_name
        end
      end
    end
  end
end
