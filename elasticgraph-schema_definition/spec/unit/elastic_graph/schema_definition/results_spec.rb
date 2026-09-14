# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/test_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe Results do
      context "without the JSON ingestion extension" do
        let(:results) { TestSupport.define_schema(schema_element_name_form: :snake_case, extension_modules: []) }

        it "reports no available JSON schema versions" do
          expect(results.available_json_schema_versions).to eq Set.new
        end

        it "raises a missing artifact error for a requested JSON schema version" do
          expect {
            results.json_schemas_for(1)
          }.to raise_error Errors::MissingSchemaArtifactError, a_string_including("JSON schema", "JSONIngestion::SchemaDefinition::APIExtension")
        end

        it "raises a missing artifact error for the latest JSON schema version" do
          expect {
            results.latest_json_schema_version
          }.to raise_error Errors::MissingSchemaArtifactError, a_string_including("JSON schema", "JSONIngestion::SchemaDefinition::APIExtension")
        end
      end
    end
  end
end
