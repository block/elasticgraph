# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe APIExtension do
        it "registers the JSON ingestion indexer extension" do
          runtime_metadata = define_schema(schema_element_name_form: "snake_case") do |schema|
            schema.object_type "Widget" do |type|
              type.field "id", "ID!"
              type.index "widgets"
            end
          end.runtime_metadata

          expect(runtime_metadata.indexer_extension_modules.map(&:extension_ref)).to include(
            SchemaArtifacts::RuntimeMetadata::Extension.new(
              IndexerExtension,
              "elastic_graph/json_ingestion/indexer_extension",
              {}
            ).to_dumpable_hash
          )
        end
      end
    end
  end
end
