# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Apollo
    module SchemaDefinition
      # The Apollo `_Entity` type is a type union of _all_ entity subtypes in an ElasticGraph schema.
      # However, unlike a normal union type:
      #
      # - `_Entity` is never an indexed type, and should not be treated as one (even though its subtypes are all indexed, which would
      #   usually cause it to be treated as indexed!).
      # - A merged set of `graphql_fields_by_name` cannot be safely computed. That method raises errors if a field with the same name
      #   has conflicting definitions on different subtypes, but we must allow that on `_Entity` subtypes.
      #
      # @private
      module EntityTypeExtension
        def graphql_fields_by_name
          {}
        end

        def indexed?
          false
        end
      end
    end
  end
end
