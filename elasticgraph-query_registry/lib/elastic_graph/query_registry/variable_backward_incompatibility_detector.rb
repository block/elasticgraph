# Copyright 2024 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module QueryRegistry
    # Responsible for comparing old and new variable type info to see if any changes are backwards
    # incompatible (and thus my break the client). Incompatibilities are identified by path and described.
    class VariableBackwardIncompatibilityDetector
      # Entry point. Given the old variables for an operation, and the new variables for it, describes
      # any backward incompatibilities in them.
      def detect(old_op_vars:, new_op_vars:)
        detect_incompatibilities(old_op_vars, new_op_vars, "$", "variable")
      end

      private

      # Given an `old` and `new` hash (which could be hashes of variables, or hashes of object fields),
      # describes the incompatibities in them.
      def detect_incompatibilities(old, new, path, entry_type)
        removals = old.keys - new.keys
        additions = new.keys - old.keys
        commonalities = old.keys & new.keys

        incompatible_removals = removals.map do |name|
          # All removals are incompatible, because the client might pass a value for the variable or field.
          Incompatibility.new("#{path}#{name}", "removed")
        end

        incompatible_commonalities = commonalities.flat_map do |name|
          incompatibilities_for("#{path}#{name}", normalize_type_info(old.fetch(name)), normalize_type_info(new.fetch(name)))
        end

        incompatible_additions = additions.filter_map do |name|
          # Additions are only incompatible if it's required (non-nullable).
          _ = if normalize_type_info(new.fetch(name)).fetch("type").end_with?("!")
            Incompatibility.new("#{path}#{name}", "new required #{entry_type}")
          end
        end

        incompatible_removals + incompatible_commonalities + incompatible_additions
      end

      # Describes the incompatibilities between the old and new type info.
      def incompatibilities_for(path, old_type_info, new_type_info)
        type_incompatibilities(path, old_type_info.fetch("type"), new_type_info.fetch("type")) +
          enum_value_incompatibilities(path, old_type_info["values"], new_type_info["values"]) +
          object_field_incompatibilities(path, old_type_info["fields"], new_type_info["fields"])
      end

      # Describes the incompatibilities between the old and new type names.
      def type_incompatibilities(path, old_type, new_type)
        if new_type == "#{old_type}!"
          # If the variable or field is being required for the first time, the client may not pass a value
          # for it and could be broken by this change.
          [Incompatibility.new(path, "required for the first time")]
        elsif old_type == "#{new_type}!"
          [] # nullability was relaxed. That can't break the client so it's fine.
        elsif new_type == old_type
          [] # the type did not change.
        else
          # The type name changed. While some type name changes are compatible (e.g. from `ID` to `String`),
          # we don't attempt to figure things out at that granularity.
          [Incompatibility.new(path, "type changed from `#{old_type}` to `#{new_type}`")]
        end
      end

      # Describes the incompatibilities between the old and new enum values for a field or variable.
      def enum_value_incompatibilities(path, old_enum_values, new_enum_values)
        return [] unless old_enum_values && new_enum_values
        removed_values = old_enum_values - new_enum_values
        return [] if removed_values.empty?

        # Removed enum values could break the client if it ever passes a removed value in a query.
        [Incompatibility.new(path, "removed enum values: #{removed_values.join(", ")}")]
      end

      # Describes the incompatibilities between old and new object fields via recursion.
      def object_field_incompatibilities(path, old_fields, new_fields)
        return [] unless old_fields && new_fields
        detect_incompatibilities(old_fields, new_fields, "#{path}.", "field")
      end

      # Handles the fact that `type_info` can sometimes be a simple string, normalizing
      # it to a hash so that we can consistently treat all type infos as hashes with a `type` field.
      def normalize_type_info(type_info)
        return {"type" => type_info} if type_info.is_a?(::String)
        _ = type_info
      end

      # Represents a single incompatibility.
      Incompatibility = ::Data.define(:path, :explanation) do
        # @implements Incompatibility
        def description
          "#{path} (#{explanation})"
        end
      end
    end
  end
end
