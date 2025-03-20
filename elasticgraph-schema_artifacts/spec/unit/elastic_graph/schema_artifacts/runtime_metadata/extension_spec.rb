# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/schema_artifacts/runtime_metadata/extension"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"
require "support/example_extensions/missing_instance_method"
require "support/example_extensions/valid"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe Extension do
        let(:loader) { ExtensionLoader.new(Class.new) }

        it "can roundtrip through a primitive ruby hash for easy serialization and deserialization" do
          extension = loader.load("ElasticGraph::Extensions::Valid", from: "support/example_extensions/valid", config: {foo: "bar"})
          hash = extension.to_dumpable_hash

          expect(hash).to eq({
            "extension_config" => {"foo" => "bar"},
            "extension_name" => "ElasticGraph::Extensions::Valid",
            "require_path" => "support/example_extensions/valid"
          })

          reloaded_extension = Extension.load_from_hash(hash, via: loader)

          expect(reloaded_extension).to eq(extension)
        end

        it "supports verification against an interface definition" do
          valid_extension = Extension.new(
            extension_class: Extensions::Valid,
            require_path: "support/example_extensions/valid",
            extension_config: {}
          )

          expect {
            valid_extension.verify_against(ExampleInterfaceDef)
          }.not_to raise_error

          invalid_extension = Extension.new(
            extension_class: Extensions::MissingInstanceMethod,
            require_path: "support/example_extensions/missing_instance_method",
            extension_config: {}
          )

          expect {
            invalid_extension.verify_against(ExampleInterfaceDef)
          }.to raise_error Errors::InvalidExtensionError, a_string_including("instance_method1")
        end
      end

      class ExampleInterfaceDef
        def self.class_method(a, b)
        end

        def instance_method1
        end

        def instance_method2(foo:)
        end
      end
    end
  end
end
