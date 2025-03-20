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
require "elastic_graph/schema_definition/mixins/supports_default_value"
require "elastic_graph/schema_definition/mixins/verifies_graphql_name"

module ElasticGraph
  module SchemaDefinition
    # Namespace for classes which represent GraphQL schema elements.
    module SchemaElements
      # Represents a [GraphQL argument](https://spec.graphql.org/October2021/#sec-Language.Arguments).
      #
      # @!attribute [r] schema_def_state
      #   @return [State] state of the schema
      # @!attribute [r] parent_field
      #   @return [Field] field which has this argument
      # @!attribute [r] name
      #   @return [String] name of the argument
      # @!attribute [r] original_value_type
      #   @return [TypeReference] type of the argument, as originally provided
      #   @see #value_type
      class Argument < Struct.new(:schema_def_state, :parent_field, :name, :original_value_type)
        prepend Mixins::VerifiesGraphQLName
        prepend Mixins::SupportsDefaultValue
        include Mixins::HasDocumentation
        include Mixins::HasDirectives
        include Mixins::HasReadableToSAndInspect.new { |a| "#{a.parent_field.parent_type.name}.#{a.parent_field.name}(#{a.name}: #{a.value_type})" }

        # @return [String] GraphQL SDL form of the argument
        def to_sdl
          "#{formatted_documentation}#{name}: #{value_type}#{default_value_sdl}#{directives_sdl(prefix_with: " ")}"
        end

        # When the argument type is an enum, and we're configured with different naming for input vs output enums,
        # we need to convert the value type to its input form. Note that this intentionally happens lazily (rather than
        # doing this when `Argument` is instantiated), because the referenced type need not exist when the argument
        # is defined, and we may not be able to figure out if it's an enum until the type has been defined. So, we
        # apply this lazily.
        #
        # @return [TypeReference] the type of the argument
        # @see #original_value_type
        def value_type
          original_value_type.to_final_form(as_input: true)
        end
      end
    end
  end
end
