# Copyright 2024 - 2026 Block, Inc.
#
# Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.
#
# frozen_string_literal: true

require "elastic_graph/proto/schema_definition/enum_type_extension"
require "elastic_graph/proto/schema_definition/object_interface_and_union_extension"
require "elastic_graph/proto/schema_definition/results_extension"
require "elastic_graph/proto/schema_definition/scalar_type_extension"
require "elastic_graph/proto/schema_definition/schema_artifact_manager_extension"

module ElasticGraph
  module Proto
    module SchemaDefinition
      # Extension module applied to Factory to add proto support.
      module FactoryExtension
        def new_enum_type(name)
          super(name) do |type|
            type.extend EnumTypeExtension
            yield type if block_given?
          end
        end

        def new_interface_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            yield type if block_given?
          end
        end

        def new_object_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            yield type if block_given?
          end
        end

        def new_scalar_type(name)
          super(name) do |type|
            type.extend ScalarTypeExtension
            yield type if block_given?
          end
        end

        def new_union_type(name)
          super(name) do |type|
            type.extend ObjectInterfaceAndUnionExtension
            yield type if block_given?
          end
        end

        def new_results
          super.tap do |results|
            results.extend ResultsExtension
          end
        end

        def new_schema_artifact_manager(...)
          super.tap do |manager|
            manager.extend SchemaArtifactManagerExtension
          end
        end
      end
    end
  end
end
