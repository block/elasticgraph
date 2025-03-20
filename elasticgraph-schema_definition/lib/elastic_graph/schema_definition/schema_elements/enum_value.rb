# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/mixins/has_directives"
require "elastic_graph/schema_definition/mixins/has_documentation"
require "elastic_graph/schema_definition/mixins/has_readable_to_s_and_inspect"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Represents a value of a [GraphQL enum type](https://spec.graphql.org/October2021/#sec-Enums).
      #
      # @!attribute [r] schema_def_state
      #   @return [State] state of the schema
      # @!attribute [r] name
      #   @return [String] name of the value
      # @!attribute [r] runtime_metadata
      #   @return [SchemaElements::RuntimeMetadata::Enum::Value] runtime metadata
      class EnumValue < Struct.new(:schema_def_state, :name, :runtime_metadata)
        prepend Mixins::VerifiesGraphQLName
        include Mixins::HasDocumentation
        include Mixins::HasDirectives
        include Mixins::HasReadableToSAndInspect.new { |v| v.name }

        # @private
        def initialize(schema_def_state, name, original_name)
          runtime_metadata = SchemaArtifacts::RuntimeMetadata::Enum::Value.new(
            sort_field: nil,
            datastore_value: nil,
            datastore_abbreviation: nil,
            alternate_original_name: (original_name if original_name != name)
          )

          super(schema_def_state, name, runtime_metadata)
          yield self
        end

        # @return [String] GraphQL SDL form of the enum value
        def to_sdl
          "#{formatted_documentation}#{name}#{directives_sdl(prefix_with: " ")}"
        end

        # Duplicates this enum value on another {EnumType}.
        #
        # @param other_enum_type [EnumType] enum type to duplicate this value onto
        # @return [void]
        def duplicate_on(other_enum_type)
          other_enum_type.value name do |v|
            v.documentation doc_comment
            directives.each { |dir| dir.duplicate_on(v) }
            v.update_runtime_metadata(**runtime_metadata.to_h)
          end
        end

        # Updates the runtime metadata.
        #
        # @param [Hash<Symbol, Object>] updates to apply to the runtime metadata
        # @return [void]
        def update_runtime_metadata(**updates)
          self.runtime_metadata = runtime_metadata.with(**updates)
        end

        private :runtime_metadata=
      end
    end
  end
end
