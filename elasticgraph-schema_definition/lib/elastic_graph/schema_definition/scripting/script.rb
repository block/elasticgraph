# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "digest/md5"
require "elastic_graph/support/memoizable_data"

module ElasticGraph
  module SchemaDefinition
    module Scripting
      # @private
      class Script < Support::MemoizableData.define(:name, :source, :language, :context)
        # The id we use when storing the script in the datastore. The id is based partially on a hash of
        # the source code to make script safely evolveable: when the source code of a script changes, its
        # id changes, and the old and new versions continue to be accessible in the datastore, allowing
        # old and new versions of the deployed ElasticGraph application to be running at the same time
        # (as happens during a zero-downtime rolled-out deploy). Scripts are invoked by their id, so we
        # can trust that when the code tries to use a specific version of a script, it'll definitely use
        # that version.
        def id
          @id ||= "#{context}_#{name}_#{::Digest::MD5.hexdigest(source)}"
        end

        # The `name` scoped with the `context`. Due to how we structure static scripts on
        # the file system (nested under a directory that names the `context`), a given `name`
        # is only guaranteed to be unique within the scope of a given `context`. The `scoped_name`
        # is how we will refer to a script from elsewhere in the code when we want to use it.
        def scoped_name
          @scoped_name ||= "#{context}/#{name}"
        end

        def to_artifact_payload
          {
            "context" => context,
            "script" => {
              "lang" => language,
              "source" => source
            }
          }
        end
      end
    end
  end
end
