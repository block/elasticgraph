# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/component_extension"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe ComponentExtension do
        it "loads extension lazily" do
          component_extension = ComponentExtension.new(
            extension_ref: {
              "name" => "ElasticGraph::Extensions::Valid",
              "require_path" => "support/example_extensions/valid"
            }
          )

          extension = component_extension.load_extension

          expect(extension).to be_a(RuntimeMetadata::Extension)
          expect(extension.extension_class).to be_a(::Module).and have_attributes(name: "ElasticGraph::Extensions::Valid")
        end
      end
    end
  end
end
