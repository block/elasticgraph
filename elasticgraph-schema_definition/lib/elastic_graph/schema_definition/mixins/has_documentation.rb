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
      # Supports GraphQL documentation.
      module HasDocumentation
        # @dynamic doc_comment, doc_comment=
        # @!attribute doc_comment
        # @return [String, nil] current documentation string for the schema element
        attr_accessor :doc_comment

        # Sets the documentation of the schema element.
        #
        # @param comment [String] the documentation string
        # @return [void]
        #
        # @example Define documentation on an object type and on a field
        #   ElasticGraph.define_schema do |schema|
        #     schema.object_type "Campaign" do |t|
        #       t.documentation "A marketing campaign."
        #
        #       t.field "id", "ID" do |f|
        #         f.documentation <<~EOS
        #           The identifier of the campaign.
        #
        #           Note: this is randomly generated.
        #         EOS
        #       end
        #     end
        #   end
        def documentation(comment)
          self.doc_comment = comment
        end

        # Appends some additional documentation to the existing documentation string.
        #
        # @param comment [String] additional documentation
        # @return [void]
        def append_to_documentation(comment)
          new_documentation = doc_comment ? "#{doc_comment}\n\n#{comment}" : comment
          documentation(new_documentation)
        end

        # Formats the documentation using GraphQL SDL syntax.
        #
        # @return [String] formatted documentation string
        def formatted_documentation
          return nil unless (comment = doc_comment)
          %("""\n#{comment.chomp}\n"""\n)
        end

        # Generates a documentation string that is derived from the schema elements existing documentation.
        #
        # @param intro [String] string that goes before the schema element's existing documentation
        # @param outro [String, nil] string that goes after the schema element's existing documentation
        # @return [String]
        def derived_documentation(intro, outro = nil)
          outro &&= "\n\n#{outro}."
          return "#{intro}.#{outro}" unless doc_comment

          quoted_doc = doc_comment.split("\n").map { |line| "> #{line}" }.join("\n")
          "#{intro}:\n\n#{quoted_doc}#{outro}"
        end
      end
    end
  end
end
