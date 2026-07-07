# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto_ingestion/schema_definition/api_extension"
require "elastic_graph/spec_support/schema_definition_helpers"

module ElasticGraph
  module ProtoIngestion
    module SchemaDefinition
      RSpec.describe APIExtension do
        include_context "SchemaDefinitionHelpers"

        it "can be used as a schema definition extension module, without customizing the schema definition yet" do
          with_extension, without_extension = [[APIExtension], []].map do |extension_modules|
            define_schema(schema_element_name_form: "snake_case", extension_modules: extension_modules) do |schema|
              schema.object_type "Widget" do |t|
                t.field "id", "ID!"
                t.index "widgets"
              end
            end.graphql_schema_string
          end

          expect(with_extension).to eq(without_extension)
        end
      end
    end
  end
end
