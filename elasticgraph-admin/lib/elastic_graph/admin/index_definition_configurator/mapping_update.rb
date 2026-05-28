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
        # Elasticsearch/OpenSearch do not support removing mapping fields from an index. Index templates
        # allow it, but doing so can break old indexer versions that still expect those fields to exist.
        # Preserve current fields when building update payloads and diffs, while still allowing updates to
        # existing field parameters and additions of new fields.
        def self.merge_existing_fields_into(desired_object, current_object)
          desired_properties = desired_object.fetch("properties") { _ = {} }
          current_properties = current_object.fetch("properties") { _ = {} }

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
