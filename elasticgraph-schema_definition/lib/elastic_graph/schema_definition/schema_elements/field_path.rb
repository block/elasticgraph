# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      # Represents a potentially nested path to a field.
      #
      # @private
      class FieldPath < Data.define(:first_part, :last_part, :path_parts)
        # The type of the field (based purely on the last part; the parent parts aren't interesting here).
        def type
          last_part.type
        end

        def path
          path_parts.map(&:name).join(".")
        end

        # The full path to the field in the index.
        def path_in_index
          path_parts.map(&:name_in_index).join(".")
        end

        # The full name of the field path, including the parent type name, such as "Widget.nested.some_field".
        def fully_qualified_path
          "#{first_part.parent_type.name}.#{path}"
        end

        # The full name of the field path in the index, including the parent type name, such as "Widget.nested.some_field".
        def fully_qualified_path_in_index
          "#{first_part.parent_type.name}.#{path_in_index}"
        end

        # The full description of the field path, including the parent type name, and field type,
        # such as "Widget.nested.some_field: ID".
        def full_description
          "#{fully_qualified_path}: #{type.name}"
        end

        # We hide `new` because `FieldPath` is only intended to be instantiated from a `Resolver` instance.
        # Importantly, `Resolver` provides an invariant that we want: a `FieldPath` is never instantiated
        # with an empty list of path parts. (This is important for the steep type checking, so it can count
        # on `last_part` being non-nil).
        private_class_method :new

        # Responsible for resolving a particular field path (given as a string) into a `FieldPath` object.
        #
        # Cannot be instantiated until the user has finished defining the schema.
        # If we allowed it to be used before then, it creates a situation where the order of definition matters.
        # In addition, this class optimizes performance by memoizing some things based on the current state, and
        # if the state is updated after an instance is created, inaccurate results could be produced.
        class Resolver
          def initialize(state)
            unless state.user_definition_complete
              raise Errors::SchemaError,
                "A `FieldPath::Resolver` cannot be created before the user definition of the schema is complete."
            end

            @indexing_fields_by_public_name_by_type = ::Hash.new do |hash, type|
              hash[type] = type
                .indexing_fields_by_name_in_index
                .values
                .to_h { |f| [f.name, f] }
            end
          end

          # Resolves the given `path_string` relative to the given `type`.
          # Returns `nil` if no field at that path can be found.
          #
          # Requires a block which will be called to determine if a parent field is valid to resolve through.
          # For example, the caller may want to disallow all parent list fields, or disallow `nested` parent
          # list fields while allowing `object` parent list fields.
          def resolve_public_path(type, path_string)
            field = nil # : Field?

            path_parts = path_string.split(".").map do |field_name|
              return nil unless type
              return nil if field && !yield(field)
              return nil unless (field = @indexing_fields_by_public_name_by_type.dig(type, field_name))
              type = field.type.unwrap_list.as_object_type
              field
            end

            return nil if path_parts.empty?

            FieldPath.send(:new, path_parts.first, path_parts.last, path_parts)
          end

          # Determines the nested paths in the given `path_string`
          # Returns `nil` if no field at that path can be found, and
          # returns `[]` if no nested paths are found.
          #
          # Nested paths are represented as the full path to the nested fields
          # For example: a `path_string` of "foo.bar.baz" might have
          # nested paths ["foo", "foo.bar.baz"]
          def determine_nested_paths(type, path_string)
            field_path = resolve_public_path(type, path_string) { true }
            return nil unless field_path

            parts_so_far = [] # : ::Array[::String]
            field_path.path_parts.filter_map do |field|
              parts_so_far << field.name
              parts_so_far.join(".") if field.nested?
            end
          end
        end
      end
    end
  end
end
