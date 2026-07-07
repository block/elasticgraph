# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/extension"
require "elastic_graph/schema_artifacts/runtime_metadata/extension_loader"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe ExtensionLoader do
        let(:loader) { ExtensionLoader.new(ExampleExtension) }

        it "loads an extension class matching the provided constant" do
          extension = loader.load("ElasticGraph::Extensions::Valid", from: "support/example_extensions/valid", config: {})

          expect(extension).to eq_extension(ElasticGraph::Extensions::Valid, from: "support/example_extensions/valid", config: {})
        end

        it "loads an extension module matching the provided constant" do
          extension = loader.load("ElasticGraph::Extensions::ValidModule", from: "support/example_extensions/valid_module", config: {})

          expect(extension).to eq_extension(ElasticGraph::Extensions::ValidModule, from: "support/example_extensions/valid_module", config: {})
        end

        it "can load an extension when the constant is prefixed with `::`" do
          extension = loader.load("::ElasticGraph::Extensions::Valid", from: "support/example_extensions/valid", config: {})

          expect(extension).to eq_extension(ElasticGraph::Extensions::Valid, from: "support/example_extensions/valid", config: {})
        end

        it "memoizes the loading of the extension, avoiding the cost of re-loading an already loaded extension, while allowing differing config" do
          allow(loader).to receive(:require).and_call_original
          allow(::Object).to receive(:const_get).and_call_original

          extension1 = loader.load("ElasticGraph::Extensions::Valid", from: "support/example_extensions/valid", config: {"size" => 10})
          extension2 = loader.load("ElasticGraph::Extensions::Valid", from: "support/example_extensions/valid", config: {"size" => 20})

          expect(extension1).to eq_extension(ElasticGraph::Extensions::Valid, from: "support/example_extensions/valid", config: {"size" => 10})
          expect(extension2).to eq_extension(ElasticGraph::Extensions::Valid, from: "support/example_extensions/valid", config: {"size" => 20})

          expect(loader).to have_received(:require).once
          expect(::Object).to have_received(:const_get).once
        end

        it "raises a clear error if a constant is re-loaded but with a different `from` argument" do
          loader.load("ElasticGraph::Extensions::Valid", from: "support/example_extensions/valid", config: {})

          expect {
            loader.load("ElasticGraph::Extensions::Valid", from: "support/example_extensions/additional_methods", config: {})
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::Valid",
            "cannot be loaded from `support/example_extensions/additional_methods`",
            "already been loaded from `support/example_extensions/valid`"
          )
        end

        it "raises a clear error when the `from:` arg isn't a valid require path" do
          expect {
            loader.load("ElasticGraph::Extensions::Valid", from: "support/example_extensions/not_a_file_name", config: {})
          }.to raise_error LoadError, a_string_including("support/example_extensions/not_a_file_name")
        end

        it "raises a clear error when the constant name is not defined after attempting to load the extension" do
          expect {
            loader.load("ElasticGraph::Extensions::Typo", from: "support/example_extensions/valid", config: {})
          }.to raise_error NameError, a_string_including("ElasticGraph::Extensions::Typo")
        end

        it "verifies the extension matches the interface definition" do
          expect {
            loader.load("ElasticGraph::Extensions::MissingInstanceMethod", from: "support/example_extensions/missing_instance_method", config: {})
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::MissingInstanceMethod",
            "Missing instance methods", "instance_method1"
          )
        end

        it "verifies that the extension is a class or module" do
          expect {
            loader.load("ElasticGraph::Extensions::NotAClassOrModule", from: "support/example_extensions/not_a_class_or_module", config: {})
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::NotAClassOrModule", "not a class or module"
          ).and(excluding("class_method", "instance_method1", "instance_method2"))
        end

        it "verifies that the extension name matches the provided name" do
          expect {
            loader.load("ElasticGraph::Extensions::NameMismatch", from: "support/example_extensions/name_mismatch", config: {})
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::NameMismatch",
            "differs from the provided extension name",
            "ElasticGraph::Extensions::ModuleWithWrongName"
          )
        end

        context "with an instantiable extension interface" do
          let(:loader) { ExtensionLoader.new(ExampleInstantiableExtension) }

          it "returns a valid implementation" do
            extension = loader.load("ElasticGraph::Extensions::ValidInstantiable", from: "support/example_extensions/valid_instantiable", config: {})

            expect(extension).to eq_extension(ElasticGraph::Extensions::ValidInstantiable, from: "support/example_extensions/valid_instantiable", config: {})
          end
        end

        describe ".load_component_extensions", :in_temp_dir do
          it "loads the extension modules from disk" do
            ::File.write("eg_extension_module1.rb", <<~EOS)
              module EgExtensionModule1
              end
            EOS

            ::File.write("eg_extension_module2.rb", <<~EOS)
              module EgExtensionModule2
              end
            EOS

            extension_modules = ExtensionLoader.load_component_extensions([
              {"name" => "EgExtensionModule1", "require_path" => "./eg_extension_module1"},
              {"name" => "EgExtensionModule2", "require_path" => "./eg_extension_module2"}
            ])

            expect(extension_modules).to eq([::EgExtensionModule1, ::EgExtensionModule2])
          end

          it "raises a clear error if an extension can't be loaded" do
            expect {
              ExtensionLoader.load_component_extensions([
                {"name" => "NotReal", "require_path" => "./not_real"}
              ])
            }.to raise_error LoadError, a_string_including("not_real")
          end

          it "raises a clear error if a named extension is not a module" do
            ::File.write("eg_extension_class1.rb", <<~EOS)
              class EgExtensionClass1
              end
            EOS

            expect {
              ExtensionLoader.load_component_extensions([
                {"name" => "EgExtensionClass1", "require_path" => "./eg_extension_class1"}
              ])
            }.to raise_error a_string_including("not a module")

            ::File.write("eg_extension_object1.rb", <<~EOS)
              EgExtensionObject1 = Object.new
            EOS

            expect {
              ExtensionLoader.load_component_extensions([
                {"name" => "EgExtensionObject1", "require_path" => "./eg_extension_object1"}
              ])
            }.to raise_error a_string_including("not a class or module")
          end
        end

        def eq_extension(extension_class, from:, config:)
          eq(Extension.new(extension_class, from, config))
        end
      end

      class ExampleExtension
        def self.class_method(a, b)
        end

        def instance_method1
        end

        def instance_method2(foo:)
        end
      end

      class ExampleInstantiableExtension
        def initialize(some_arg:)
          # No body needed
        end

        def do_it
        end
      end
    end
  end
end
