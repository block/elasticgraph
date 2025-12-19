# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "time"

module ElasticGraph
  class Indexer
    module IndexingPreparers
      class DateTime
        # Here we normalize DateTime strings to consistent 3-digit millisecond precision.
        # This is critical for min/max value tracking which uses string comparison via
        # Painless's `.compareTo()` method.
        #
        # Without consistent precision, string comparison produces incorrect results:
        #   "2025-12-19T04:15:47.53Z" vs "2025-12-19T04:15:47.531Z"
        #                        ^                              ^
        #                       'Z' (ASCII 90)  >  '1' (ASCII 49)
        #
        # This would incorrectly determine that `.53Z > .531Z`.
        #
        # By normalizing all DateTime values to 3-digit precision, we ensure:
        #   "2025-12-19T04:15:47.530Z" < "2025-12-19T04:15:47.531Z"
        def self.prepare_for_indexing(value)
          return value if value.nil?
          time = ::Time.iso8601(value)
          time.getutc.iso8601(DATE_TIME_PRECISION)
        rescue ::ArgumentError, ::TypeError
          # If the value is not a valid ISO8601 string, return it as-is
          # and let the datastore reject it if necessary.
          value
        end
      end
    end
  end
end
