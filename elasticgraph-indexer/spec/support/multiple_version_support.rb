# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  class Indexer
    ::RSpec.shared_context "MultipleVersionSupport" do
      include_context "SchemaDefinitionHelpers"

      def build_indexer_with_multiple_schema_versions(schema_versions:)
        results_by_version = schema_versions.to_h do |json_schema_version, prior_def|
          results = define_schema(schema_element_name_form: :snake_case, json_schema_version: json_schema_version, &prior_def)
          [json_schema_version, results]
        end

        json_schemas_by_version = results_by_version.to_h do |version, results|
          [version, results.json_schemas_for(version)]
        end

        artifacts = results_by_version.fetch(results_by_version.keys.max)

        allow(artifacts).to receive(:available_json_schema_versions).and_return(json_schemas_by_version.keys.to_set)
        allow(artifacts).to receive(:latest_json_schema_version).and_return(json_schemas_by_version.keys.max)
        allow(artifacts).to receive(:json_schemas_for) do |version|
          json_schemas_by_version.fetch(version)
        end

        build_indexer(schema_artifacts: artifacts)
      end
    end
  end
end
