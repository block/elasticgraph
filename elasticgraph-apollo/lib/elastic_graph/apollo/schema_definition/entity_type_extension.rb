# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Apollo
    module SchemaDefinition
      # The Apollo `_Entity` type is a union of all entity types in an ElasticGraph schema. These overrides
      # prevent ElasticGraph from treating `_Entity` like a normal indexed union type, which would trigger
      # unwanted derived schema generation and validation.
      #
      # @private
      module EntityTypeExtension
        # A merged set of `graphql_fields_by_name` cannot be safely computed. That method raises errors if a field with
        # the same name has conflicting definitions on different subtypes, but we must allow that on `_Entity` subtypes.
        def graphql_fields_by_name
          {}
        end

        # `_Entity` is never a root document type, and should not be treated as one (even though its subtypes are all
        # root document types, which would usually cause it to be treated as a root document type!).
        def root_document_type?
          false
        end

        # `_Entity` is never directly queryable from the root `Query` type. It's queried via the apollo
        # `_entities(representations: ...)` field instead.
        def directly_queryable?
          false
        end
      end
    end
  end
end
