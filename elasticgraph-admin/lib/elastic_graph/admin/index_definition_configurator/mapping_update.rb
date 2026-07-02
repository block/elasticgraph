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
        empty_properties = {} # : ::Hash[::String, untyped]
        EMPTY_PROPERTIES = empty_properties.freeze

        # Elasticsearch/OpenSearch do not support removing mapping fields from an index. Preserve current
        # fields when building concrete index update payloads and diffs, while still allowing updates to
        # existing field parameters and additions of new fields.
        def self.merge_existing_fields_into(desired_object, current_object)
          desired_properties = desired_object.fetch("properties", EMPTY_PROPERTIES)
          current_properties = current_object.fetch("properties", EMPTY_PROPERTIES)

          merged_properties = desired_properties.merge(current_properties) do |_key, desired, current|
            if current.is_a?(::Hash) && current.key?("properties") && desired.key?("properties")
              merge_existing_fields_into(desired, current)
            else
              desired
            end
          end

          desired_object.merge("properties" => merged_properties)
        end
      end
    end
  end
end
