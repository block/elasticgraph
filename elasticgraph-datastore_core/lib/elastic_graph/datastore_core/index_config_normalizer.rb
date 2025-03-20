# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  class DatastoreCore
    module IndexConfigNormalizer
      # These are settings that the datastore exposes when you fetch an index, but that you can
      # never set. We need to ignore them when figuring out what settings to update.
      #
      # Note: `index.routing.allocation.include._tier_preference` is not a read-only setting, but
      # we want to treat it as one, because (1) Elasticsearch 7.10+ sets it and (2) we do not want
      # to ever write it at this time.
      #
      # Note: `index.history.uuid` is a weird setting that sometimes shows up in managed AWS OpenSearch
      # clusters, but only on _some_ indices. It's not documented and we don't want to mess with it here,
      # so we want to treat it as a read only setting.
      READ_ONLY_SETTINGS = %w[
        index.creation_date
        index.history.uuid
        index.provided_name
        index.replication.type
        index.routing.allocation.include._tier_preference
        index.uuid
        index.version.created
        index.version.upgraded
      ]

      # Normalizes the provided index configuration so that it is in a stable form that we can compare to what
      # the datastore returns when we query it for the configuration of an index. This includes:
      #
      # - Dropping read-only settings that we never interact with but that the datastore automatically sets on an index.
      #   Omitting them makes it easier for us to compare our desired configuration to what is in the datastore.
      # - Converting setting values to a normalized string form. The datastore oddly returns setting values as strings
      #   (e.g. `"false"` or `"7"` instead of `false` or `7`), so this matches that behavior.
      # - Drops `type: object` from a mapping when there are `properties` because the datastore omits it in that
      #   situation, treating it as the default type.
      def self.normalize(index_config)
        if (settings = index_config["settings"])
          index_config = index_config.merge("settings" => normalize_settings(settings))
        end

        if (mappings = index_config["mappings"])
          index_config = index_config.merge("mappings" => normalize_mappings(mappings))
        end

        index_config
      end

      def self.normalize_mappings(mappings)
        return mappings unless (properties = mappings["properties"])

        mappings = mappings.except("type") if mappings["type"] == "object"
        mappings.merge("properties" => properties.transform_values { |prop| normalize_mappings(prop) })
      end

      def self.normalize_settings(settings)
        settings
          .except(*READ_ONLY_SETTINGS)
          .to_h { |name, value| [name, normalize_setting_value(value)] }
      end

      private_class_method def self.normalize_setting_value(value)
        case value
        when nil
          nil
        when ::Array
          value.map { |v| normalize_setting_value(v) }
        else
          value.to_s
        end
      end
    end
  end
end
