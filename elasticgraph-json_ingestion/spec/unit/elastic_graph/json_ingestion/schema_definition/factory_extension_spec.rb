# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/json_ingestion/schema_definition/factory_extension"

module ElasticGraph
  module JSONIngestion
    module SchemaDefinition
      RSpec.describe FactoryExtension do
        let(:factory_class) do
          base_class = ::Class.new do
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

        it "extends results and schema artifact managers with JSON schema behavior" do
          factory = factory_class.new

          expect(factory.new_results).to be_a(ResultsExtension)

          manager = factory.new_schema_artifact_manager(:positional, key: "value")
          expect(manager).to be_a(SchemaArtifactManagerExtension)
          expect(factory.last_schema_artifact_manager_args).to eq([:positional])
          expect(factory.last_schema_artifact_manager_kwargs).to eq({key: "value"})
        end

        it "extends schema elements even when no customization block is provided" do
          base_class = ::Class.new do
            def new_enum_type(name, &block)
              build_type(name, &block)
            end

            def new_interface_type(name, &block)
              build_type(name, &block)
            end

            def new_object_type(name, &block)
              build_type(name, &block)
            end

            def new_scalar_type(name, &block)
              build_type(name, &block)
            end

            def new_union_type(name, &block)
              build_type(name, &block)
            end

            private

            def build_type(name)
              ::Object.new.tap do |type|
                type.define_singleton_method(:name) { name }
                yield type
              end
            end
          end

          factory = ::Class.new(base_class) do
            prepend FactoryExtension
          end.new

          expect(factory.new_enum_type("Color")).to be_a(EnumTypeExtension)
          expect(factory.new_interface_type("Node")).to be_a(ObjectInterfaceExtension)
          expect(factory.new_object_type("Widget")).to be_a(ObjectInterfaceExtension)
          expect(factory.new_scalar_type("Boolean")).to be_a(ScalarTypeExtension)
          expect(factory.new_union_type("Result")).to be_a(UnionTypeExtension)
        end
      end
    end
  end
end
