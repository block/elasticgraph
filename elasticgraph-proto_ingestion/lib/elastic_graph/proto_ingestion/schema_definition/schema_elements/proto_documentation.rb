# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      module SchemaElements
        # Formats ElasticGraph schema element documentation as protobuf comments.
        #
        # @api private
        module ProtoDocumentation
          # Joins field or enum value definitions, separating documented entries with blank lines.
          #
          # @param definitions [Array<String>] declarations with any leading comments
          # @return [String] formatted protobuf declarations
          def self.join_definitions(definitions)
            definitions.chunk_while do |previous, following|
              !previous.include?("\n") && !following.include?("\n")
            end.map { |group| group.join("\n") }.join("\n\n")
          end

          # Formats documentation as line comments.
          #
          # @param doc_comment [String, nil] schema element documentation
          # @param indent [String] indentation to put before each comment
          # @return [Array<String>] formatted protobuf comment lines
          def self.comment_lines_for(doc_comment, indent: "")
            return [] unless doc_comment

            doc_comment.chomp.lines(chomp: true).map do |line|
              line.empty? ? "#{indent}//" : "#{indent}// #{line}"
            end
          end
        end
      end
    end
  end
end
