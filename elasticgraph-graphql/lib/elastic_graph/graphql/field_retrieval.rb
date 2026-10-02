# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/graphql/field_retrieval_plan"

module ElasticGraph
  class GraphQL
    # Strategies applied to the complete selection after resolver-side query merging.
    # @private
    module FieldRetrieval
      # Preserves source retrieval and the existing ID-only optimization.
      # @private
      class Source
        def plan(requested_fields:, request_all_fields:, highlighting:, index_definitions:)
          fields = requested_fields - ["id"]
          if request_all_fields
            FieldRetrievalPlan::SOURCE.with(reason: "source_all_fields")
          elsif fields.empty?
            FieldRetrievalPlan.new(source: false, docvalue_fields: [], reason: "metadata_only")
          else
            FieldRetrievalPlan.new(source: {includes: fields}, docvalue_fields: [], reason: "source_default")
          end
        end
      end

      # Experimental eligibility policy; this does not yet estimate retrieval cost.
      # @private
      class Automatic < Source
        # The default datastore request limit, not a measured performance threshold.
        MAX_DOCVALUE_FIELDS = 100

        def plan(requested_fields:, request_all_fields:, highlighting:, index_definitions:)
          source_plan = super
          return source_plan unless source_plan.reason == "source_default"

          fields = requested_fields - ["id"]
          reason = if highlighting
            "source_highlighting"
          elsif fields.size > MAX_DOCVALUE_FIELDS
            "source_field_limit"
          elsif index_definitions.empty? || !index_definitions.all? { |index| fields.all? { |field| index.fields_by_path[field]&.doc_values_eligible } }
            "source_ineligible_fields"
          end

          if reason
            source_plan.with(reason: reason)
          else
            FieldRetrievalPlan.new(source: false, docvalue_fields: fields, reason: "doc_values")
          end
        end
      end
    end
  end
end
