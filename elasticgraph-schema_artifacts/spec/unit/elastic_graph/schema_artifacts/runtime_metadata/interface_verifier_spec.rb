# Copyright 2024 - 2025 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/errors"
require "elastic_graph/schema_artifacts/runtime_metadata/interface_verifier"

module ElasticGraph
  module SchemaArtifacts
    module RuntimeMetadata
      RSpec.describe InterfaceVerifier do
        let(:interface_def) { ExampleExtension }

        it "allows a valid implementation" do
          expect {
            verify("ElasticGraph::Extensions::Valid", from: "support/example_extensions/valid")
          }.not_to raise_error
        end

        it "verifies the extension matches the interface definition, notifying of missing instance methods" do
          expect {
            verify("ElasticGraph::Extensions::MissingInstanceMethod", from: "support/example_extensions/missing_instance_method")
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::MissingInstanceMethod",
            "Missing instance methods", "instance_method1"
          )
        end

        it "verifies the extension matches the interface definition, notifying of missing class methods" do
          expect {
            verify("ElasticGraph::Extensions::MissingClassMethod", from: "support/example_extensions/missing_class_method")
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::MissingClassMethod",
            "Missing class methods", "class_method"
          )
        end

        it "verifies the extension matches the interface definition, notifying of argument mis-matches" do
          expect {
            verify("ElasticGraph::Extensions::ArgsMismatch", from: "support/example_extensions/args_mismatch")
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::ArgsMismatch",
            "Method signature", "def self.class_method", "def instance_method1", "def instance_method2"
          )
        end

        it "verifies that the extension is a class or module" do
          expect {
            verify("ElasticGraph::Extensions::NotAClassOrModule", from: "support/example_extensions/not_a_class_or_module")
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::NotAClassOrModule", "not a class or module"
          ).and(excluding("class_method", "instance_method1", "instance_method2"))
        end

        it "verifies that the extension name matches the provided name" do
          expect {
            verify("ElasticGraph::Extensions::NameMismatch", from: "support/example_extensions/name_mismatch")
          }.to raise_error Errors::InvalidExtensionError, a_string_including(
            "ElasticGraph::Extensions::NameMismatch",
            "differs from the provided extension name",
            "ElasticGraph::Extensions::ModuleWithWrongName"
          )
        end

        it "ignores extra methods defined on the extension beyond what the interface requires" do
          expect {
            verify("ElasticGraph::Extensions::AdditionalMethods", from: "support/example_extensions/additional_methods")
          }.not_to raise_error
        end

        context "with an instantiable extension interface" do
          let(:interface_def) { ExampleInstantiableExtension }

          it "raises an exception if the extension is missing the required `initialize` method" do
            expect {
              verify("ElasticGraph::Extensions::InitializeMissing", from: "support/example_extensions/initialize_missing")
            }.to raise_error Errors::InvalidExtensionError, a_string_including(
              "ElasticGraph::Extensions::InitializeMissing",
              "Missing instance methods: `initialize`"
            )
          end

          it "raises an exception if the extension's `initialize` accepts different arguments" do
            expect {
              verify("ElasticGraph::Extensions::InitializeDoesntMatch", from: "support/example_extensions/initialize_doesnt_match")
            }.to raise_error Errors::InvalidExtensionError, a_string_including(
              "ElasticGraph::Extensions::InitializeDoesntMatch",
              "Method signature for instance method `initialize` (`def initialize(some_arg:, another_arg:)`) does not match interface (`def initialize(some_arg:)`)"
            )
          end

          it "allows a valid implementation" do
            expect {
              verify("ElasticGraph::Extensions::ValidInstantiable", from: "support/example_extensions/valid_instantiable")
            }.not_to raise_error
          end
        end

        def verify(constant_name, from:)
          require from
          extension = ::Object.const_get(constant_name)
          InterfaceVerifier.verify(extension, against: interface_def, constant_name: constant_name)
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
