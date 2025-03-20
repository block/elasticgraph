# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module Mixins
      # Provides support for annotating any schema element with a GraphQL directive.
      module HasDirectives
        # Adds a GraphQL directive to the current schema element.
        #
        # @note If you’re using a custom directive rather than a standard GraphQL directive like `@deprecated`, you’ll also need to use
        #   {API#raw_sdl} to define the custom directive.
        #
        # @param name [String] name of the directive
        # @param arguments [Hash<String, Object>] arguments for the directive
        # @return [void]
        #
        # @example Add a standard GraphQL directive to a field
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID" do |f|
        #         f.directive "deprecated"
        #       end
        #     end
        #   end
        #
        # @example Define a custom GraphQL directive and add it to an object type
        #   ElasticGraph.define_schema do |schema|
        #     # Define a directive we can use to annotate what system a data type comes from.
        #     schema.raw_sdl "directive @sourcedFrom(system: String!) on OBJECT"
        #
        #     schema.object_type "Campaign" do |t|
        #       t.field "id", "ID"
        #       t.directive "sourcedFrom", system: "campaigns"
        #     end
        #   end
        def directive(name, arguments = {})
          directives << schema_def_state.factory.new_directive(name, arguments)
        end

        # Helper method designed for use by including classes to get the formatted directive SDL.
        #
        # @param suffix_with [String] suffix to add on the end of the SDL
        # @param prefix_with [String] prefix to add to the beginning of the SDL
        # @return [String] SDL string for the directives
        # @api private
        def directives_sdl(suffix_with: "", prefix_with: "")
          sdl = directives.map(&:to_sdl).join(" ")
          return sdl if sdl.empty?
          prefix_with + sdl + suffix_with
        end

        # @return [Array<SchemaElements::Directive>] directives attached to this schema element
        def directives
          @directives ||= []
        end
      end
    end
  end
end
