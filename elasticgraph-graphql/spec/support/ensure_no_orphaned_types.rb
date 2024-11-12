# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class GraphQL
    # Before v2.4 of the GraphQL gem, `GraphQL::Schema#types` returned _all_ types defined by the SDL string.
    # Beginning in v2.4, orphaned types (that is, types not reachable from the root `Query` type) are no longer
    # included. We have a number of unit tests that define orphaned types since we don't want or need a full
    # schema for such a test.
    #
    # To avoid issues as part of upgrading to v2.4, we need to ensure that our tests don't depend on orphaned
    # types that are unavailable in v2.4 and later. This mixin provides a simple solution: it adds on an indexed
    # type (`IndexedTypeToEnsureNoOrphans`) with a field for each defined type, ensuring that no defined types
    # are orphans.
    #
    # Apply it to an example or example group using the `:ensure_no_orphaned_types` tag.
    module EnsureNoOrphanedTypes
      def build_graphql(schema_definition: nil, **options, &block)
        schema_def = lambda do |schema|
          original_types = schema.state.types_by_name.keys
          schema_definition.call(schema)

          # If a test is taking are of defining its own indexed types, we don't need to do anything further.
          return if schema.state.object_types_by_name.values.any?(&:indexed?)

          added_types = schema.state.types_by_name.keys - original_types

          schema.object_type "IndexedTypeToEnsureNoOrphans" do |t|
            added_types.each do |type_name|
              t.field type_name, type_name
            end

            t.field "id", "ID"
            t.index "indexed_types"
          end
        end

        super(schema_definition: schema_def, **options, &block)
      end
    end

    ::RSpec.configure do |c|
      c.include EnsureNoOrphanedTypes, :ensure_no_orphaned_types
    end
  end
end
