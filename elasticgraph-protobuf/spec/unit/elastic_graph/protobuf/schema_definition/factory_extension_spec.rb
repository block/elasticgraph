# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/protobuf/schema_definition/factory_extension"

module ElasticGraph
  module Protobuf
    module SchemaDefinition
      RSpec.describe FactoryExtension do
        let(:factory_class) do
          base_class = ::Class.new do
            def new_enum_type(_name)
              type = ::Object.new
              yield type
              type
            end

            def new_interface_type(_name)
              type = ::Object.new
              yield type
              type
            end

            def new_object_type(_name)
              type = ::Object.new
              yield type
              type
            end

            def new_scalar_type(_name)
              type = ::Object.new
              yield type
              type
            end

            def new_union_type(_name)
              type = ::Object.new
              yield type
              type
            end

            def new_results
              ::Object.new
            end

            def new_schema_artifact_manager(*args, **kwargs)
              @last_schema_artifact_manager_args = args
              @last_schema_artifact_manager_kwargs = kwargs
              ::Object.new
            end

            attr_reader :last_schema_artifact_manager_args, :last_schema_artifact_manager_kwargs
          end

          ::Class.new(base_class) do
            prepend FactoryExtension
          end
        end

        it "extends enum types with enum conversion behavior" do
          type = factory_class.new.new_enum_type("Status")
          expect(type).to be_a(EnumTypeExtension)
        end

        it "extends interface and union types with object conversion behavior" do
          factory = factory_class.new
          interface_from_block = nil
          union_from_block = nil

          factory.new_interface_type("Node") { |type| interface_from_block = type }
          expect(factory.new_interface_type("Node")).to be_a(ObjectInterfaceAndUnionExtension)
          expect(interface_from_block).to be_a(ObjectInterfaceAndUnionExtension)

          factory.new_union_type("SearchResult") { |type| union_from_block = type }
          expect(factory.new_union_type("SearchResult")).to be_a(ObjectInterfaceAndUnionExtension)
          expect(union_from_block).to be_a(ObjectInterfaceAndUnionExtension)
        end

        it "extends object and scalar types and yields to provided blocks" do
          object_type = nil
          scalar_type = nil

          factory = factory_class.new
          factory.new_object_type("Account") { |type| object_type = type }
          factory.new_scalar_type("Custom") { |type| scalar_type = type }

          expect(object_type).to be_a(ObjectInterfaceAndUnionExtension)
          expect(scalar_type).to be_a(ScalarTypeExtension)
          expect(factory.new_object_type("Account")).to be_a(ObjectInterfaceAndUnionExtension)
          expect(factory.new_scalar_type("Custom")).to be_a(ScalarTypeExtension)
        end

        it "extends results and schema artifact managers" do
          factory = factory_class.new

          expect(factory.new_results).to be_a(ResultsExtension)

          manager = factory.new_schema_artifact_manager(:positional, key: "value")
          expect(manager).to be_a(SchemaArtifactManagerExtension)
          expect(factory.last_schema_artifact_manager_args).to eq([:positional])
          expect(factory.last_schema_artifact_manager_kwargs).to eq({key: "value"})
        end
      end
    end
  end
end
