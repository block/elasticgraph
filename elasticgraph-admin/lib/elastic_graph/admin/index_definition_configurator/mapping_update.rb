# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class Admin
    module IndexDefinitionConfigurator
      module MappingUpdate
        # Steep's `UnannotatedEmptyCollection` diagnostic requires the annotation to be on the line
        # containing the `{}` literal and cannot see it through `.freeze`, hence the two-step assignment.
        empty_properties = {} # : ::Hash[::String, untyped]
        EMPTY_PROPERTIES = empty_properties.freeze

        # Elasticsearch/OpenSearch do not support removing mapping fields from an index. Preserve current
        # fields when building index mapping update payloads and diffs, while still allowing updates to
        # existing field parameters and additions of new fields.
        #
        # `protected_field_paths` limits which fields missing from the desired mapping get preserved: when
        # provided, a missing field is preserved only if its path (or a descendant's path) is in the set,
        # and other missing fields are dropped from the built update. When `nil`, all missing fields are
        # preserved.
        def self.build_mapping_update(desired:, current:, protected_field_paths: nil, parent_path: "")
          desired_properties = desired.fetch("properties", EMPTY_PROPERTIES)
          current_properties = current.fetch("properties", EMPTY_PROPERTIES)

          preserved_current_properties = current_properties.select do |field_name, _|
            desired_properties.key?(field_name) || preserve_missing_field?(protected_field_paths, "#{parent_path}#{field_name}")
          end

          merged_properties = desired_properties.merge(preserved_current_properties) do |field_name, desired_value, current_value|
            if current_value.is_a?(::Hash) && current_value.key?("properties") && desired_value.key?("properties")
              build_mapping_update(
                desired: desired_value,
                current: current_value,
                protected_field_paths: protected_field_paths,
                parent_path: "#{parent_path}#{field_name}."
              )
            else
              desired_value
            end
          end

          desired.merge("properties" => merged_properties)
        end

        # A missing field is preserved if it is protected itself, or if any protected path sits underneath
        # it (dropping the field would drop the protected descendant along with it).
        def self.preserve_missing_field?(protected_field_paths, path)
          return true if protected_field_paths.nil?

          protected_field_paths.include?(path) || protected_field_paths.any? { |protected_path| protected_path.start_with?("#{path}.") }
        end
        private_class_method :preserve_missing_field?
      end
    end
  end
end
