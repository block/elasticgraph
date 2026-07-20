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
