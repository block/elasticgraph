# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/constants"
require "elastic_graph/indexer/operation/result"
require "json"

module ElasticGraph
  class Indexer
    module Operation
      # Shared response categorization logic for `Update` and `CoalescedUpdate` operations.
      # Including classes must provide `update_target` and `doc_id`.
      module UpdateCategorization
        def categorize(response)
          update = response.fetch("update")
          status = update.fetch("status")

          if noop_result?(response)
            noop_message = message_from_thrown_painless_exception(update)
              &.delete_prefix(UPDATE_WAS_NOOP_MESSAGE_PREAMBLE)

            Result.noop_of(self, noop_message)
          elsif (200..299).cover?(status)
            Result.success_of(self)
          else
            error = update.fetch("error")

            further_detail =
              if (more_detail = error["caused_by"])
                # Usually the type/reason details are nested an extra level (`caused_by.caused_by`) but sometimes
                # it's not. I think it's nested when the script itself throws an exception where as it's unnested
                # when the datastore is unable to run the script.
                more_detail = more_detail["caused_by"] if more_detail.key?("caused_by")
                " (#{more_detail["type"]}: #{more_detail["reason"]})"
              else
                "; full response: #{::JSON.pretty_generate(response)}"
              end

            Result.failure_of(self, "#{update_target.script_id}(applied to `#{doc_id}`): #{error.fetch("reason")}#{further_detail}")
          end
        end

        private

        def noop_result?(response)
          update = response.fetch("update")
          error_message = message_from_thrown_painless_exception(update).to_s
          error_message.start_with?(UPDATE_WAS_NOOP_MESSAGE_PREAMBLE) || update["result"] == "noop"
        end

        def message_from_thrown_painless_exception(update)
          update.dig("error", "caused_by", "caused_by", "reason")
        end
      end
    end
  end
end
