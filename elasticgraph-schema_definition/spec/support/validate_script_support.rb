# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"

module ElasticGraph
  module SchemaDefinition
    module ValidateScriptSupport
      def validate_script(id, payload)
        main_datastore_client.put_script(id: id, body: {script: payload.fetch("script")}, context: payload.fetch("context"))
      rescue Errors::BadDatastoreRequest => ex
        # :nocov: -- only executed when we have a script that can't compile
        message = JSON.pretty_generate(JSON.parse(ex.message.sub(/\A[^{]+/, "")))

        raise <<~EOS
          The script is invalid.

          #{payload.dig("script", "source")}

          #{"=" * 80}

          #{message}
        EOS
        # :nocov:
      end
    end
  end
end
