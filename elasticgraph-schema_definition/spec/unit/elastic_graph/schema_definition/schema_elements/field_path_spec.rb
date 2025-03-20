# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_definition/api"
require "elastic_graph/schema_definition/schema_elements/field_path"

module ElasticGraph
  module SchemaDefinition
    module SchemaElements
      class FieldPath
        RSpec.describe Resolver do
          it "can only be created after the user definition is complete, to avoid problems" do
            schema_elements = SchemaArtifacts::RuntimeMetadata::SchemaElementNames.new(form: "snake_case")
            api = API.new(schema_elements, true)

            expect {
              Resolver.new(api.state)
            }.to raise_error Errors::SchemaError, a_string_including(
              "cannot be created before the user definition of the schema is complete"
            )

            api.results # signals the definition is complete

            expect(Resolver.new(api.state)).to be_a Resolver
          end
        end
      end
    end
  end
end
