# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require_relative "runtime_metadata_support"

module ElasticGraph
  module SchemaDefinition
    RSpec.describe "RuntimeMetadata #graphql_extension_modules" do
      include_context "RuntimeMetadata support"

      it "includes any modules registered during schema definition" do
        extension_module1 = Module.new
        extension_module2 = Module.new

        metadata = define_schema do |s|
          s.register_graphql_extension extension_module1, defined_at: __FILE__
          s.register_graphql_extension extension_module2, defined_at: __FILE__

          s.object_type "Widget" do |t|
            t.field "id", "ID!"
            t.index "widgets"
          end
        end.runtime_metadata

        expect(metadata.graphql_extension_modules).to eq [
          SchemaArtifacts::RuntimeMetadata::GraphQLExtension.new(
            SchemaArtifacts::RuntimeMetadata::Extension.new(extension_module1, __FILE__, {}).to_dumpable_hash
          ),
          SchemaArtifacts::RuntimeMetadata::GraphQLExtension.new(
            SchemaArtifacts::RuntimeMetadata::Extension.new(extension_module2, __FILE__, {}).to_dumpable_hash
          )
        ]
      end
    end
  end
end
