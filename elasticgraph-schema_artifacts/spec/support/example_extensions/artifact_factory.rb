# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module Extensions
    module ArtifactFactory
      def self.from_disk(artifacts_dir, config:)
        [artifacts_dir, config]
      end

      def self.from_schema_definition(results, config:)
        [results, config]
      end
    end
  end
end
