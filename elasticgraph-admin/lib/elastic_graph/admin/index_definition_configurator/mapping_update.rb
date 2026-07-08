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
        def self.build_mapping_update(desired:, current:)
          desired_properties = desired.fetch("properties", EMPTY_PROPERTIES)
          current_properties = current.fetch("properties", EMPTY_PROPERTIES)

          merged_properties = desired_properties.merge(current_properties) do |_key, desired_value, current_value|
            if current_value.is_a?(::Hash) && current_value.key?("properties") && desired_value.key?("properties")
              build_mapping_update(desired: desired_value, current: current_value)
            else
              desired_value
            end
          end

          desired.merge("properties" => merged_properties)
        end
      end
    end
  end
end
